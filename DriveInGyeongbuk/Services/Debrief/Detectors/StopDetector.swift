//
//  StopDetector.swift
//  DriveInGyeongbuk
//
//  "한자리에 오래 서 있었는가, 그 자리가 주정차 금지구간이었는가."
//
//  ⚠️ 이 감지기에는 **데이터가 닿는 범위**라는 제약이 있다.
//     `EnforcementService` 는 목적지 반경(서버 고정 2km) 안의 금지구간만 알고 있다.
//     경로 한복판에서 선 자리가 금지구간인지는 확인할 방법이 없다.
//
//     그래서 여기서는 **확인 가능한 정차만** 사건으로 만든다. 범위 밖에서 선 것을
//     "괜찮았다"고도 "문제였다"고도 말하지 않는다 — 모르는 것을 아는 척하지 않는 쪽이,
//     이 기능이 사용자에게 거짓말을 하지 않게 하는 유일한 방법이다.
//
//  판정에 쓰는 시각은 **정차한 시각**이다. 지금 시각이 아니다. 탄력 금지구간은
//  시간대에 따라 규칙이 달라서, 오후 3시에 선 것을 밤 10시 기준으로 보면 안 된다.
//

import Foundation

nonisolated struct StopDetector: DriveEventDetecting {

    /// 이 반경 안에서만 머물렀으면 "서 있었다"고 본다(m). GPS 표류를 감안한 값이다.
    var stationaryRadiusMeters: Double = 25
    /// 이 시간 이상 서 있어야 사건으로 본다(초).
    var minimumStopSeconds: TimeInterval = 180
    /// 정차 지점과 금지구간이 이만큼 안에 있으면 그 구간에 선 것으로 본다(m).
    var zoneMatchToleranceMeters: Double = 30
    /// 출발 직후 이 시간 안의 정차는 무시한다(초). 시동 걸고 대기하는 시간이다.
    var ignoreFirstSeconds: TimeInterval = 60

    func detect(in context: DriveEventContext) -> [DriveEvent] {
        stops(in: context.recording)
            .compactMap { makeEvent(from: $0, context: context) }
    }

    // MARK: - 정차 구간 찾기

    private struct Stop {
        var samples: [DriveSample]
        var start: Date { samples.first?.timestamp ?? .distantPast }
        var end: Date { samples.last?.timestamp ?? .distantPast }
        var duration: TimeInterval { end.timeIntervalSince(start) }
        /// 정차 지점 대표 좌표. 표류를 평균으로 눌러 준다.
        var coordinate: NaverCoordinate {
            let count = Double(samples.count)
            guard count > 0 else { return NaverCoordinate(latitude: 0, longitude: 0) }
            return NaverCoordinate(
                latitude: samples.reduce(0) { $0 + $1.coordinate.latitude } / count,
                longitude: samples.reduce(0) { $0 + $1.coordinate.longitude } / count
            )
        }
    }

    /// 연속한 샘플이 한 반경 안에 머무는 구간을 찾는다.
    private func stops(in recording: DriveRecording) -> [Stop] {
        let samples = recording.samples
        guard samples.count >= 2 else { return [] }

        var result: [Stop] = []
        var index = 0

        while index < samples.count {
            let anchor = samples[index]
            var end = index

            // 기준점에서 반경을 벗어나지 않는 동안 계속 늘린다.
            while end + 1 < samples.count,
                  anchor.coordinate.distance(to: samples[end + 1].coordinate) <= stationaryRadiusMeters {
                end += 1
            }

            let stop = Stop(samples: Array(samples[index...end]))
            let startedAfter = stop.start.timeIntervalSince(recording.startedAt)

            if stop.duration >= minimumStopSeconds, startedAfter >= ignoreFirstSeconds {
                result.append(stop)
                index = end + 1
            } else {
                // 정차가 아니면 한 칸만 나아간다. 놓치는 구간이 없도록.
                index += 1
            }
        }

        return result
    }

    // MARK: - 사건 만들기

    private func makeEvent(from stop: Stop, context: DriveEventContext) -> DriveEvent? {

        let coordinate = stop.coordinate

        // 단속 데이터가 닿지 않는 자리면 아무 말도 하지 않는다.
        guard context.hasEnforcementCoverage(at: coordinate) else { return nil }

        let minutes = max(1, Int((stop.duration / 60).rounded()))
        let matched = nearestZone(to: coordinate, in: context.enforcementZones)

        guard let (zone, distance) = matched, distance <= zoneMatchToleranceMeters else {
            // 범위 안이지만 어떤 금지구간에도 걸치지 않았다. 이건 확인된 사실이라 말해도 된다.
            return DriveEvent(
                id: "",
                kind: .longStop,
                occurredAt: stop.start,
                coordinate: coordinate,
                roadName: nil,
                facts: [
                    .init("durationMinutes", minutes),
                    .init("insideRestrictedZone", false),
                    .init("checkedAgainstOfficialZoneData", true)
                ],
                summary: "Stopped for about \(minutes) min near the destination, clear of any designated restricted section.",
                relatedTopicIDs: [.noParkingZone]
            )
        }

        // 정차한 그 시각 기준으로 규칙을 다시 계산한다.
        let status = zone.schedule.status(at: stop.start)

        var facts: [DriveEvent.Fact] = [
            .init("durationMinutes", minutes),
            .init("insideRestrictedZone", true),
            .init("checkedAgainstOfficialZoneData", true),
            .init("roadName", zone.roadName),
            .init("restrictionType", zone.kind.rawValue),
            .init("restrictionTypeKorean", zone.koreanTypeName),
            .init("prohibitedAtThatTime", status.prohibitsParkingNow),
            .init("prohibitedHours", zone.schedule.summary),
            .init("metersFromZone", Int(distance.rounded()))
        ]
        if !zone.detailLocation.isEmpty {
            facts.append(.init("detailLocation", zone.detailLocation))
        }

        let summary = status.prohibitsParkingNow
            ? "Stopped for about \(minutes) min on \(zone.roadName), inside a section where parking was restricted at that hour."
            : "Stopped for about \(minutes) min on \(zone.roadName), a restricted section that was not being enforced at that hour."

        // 절대 금지구간이면 "복선 = 아예 못 선다" 쪽 설명이 먼저다.
        let topics: [DebriefTopicID] = zone.kind == .absolute
            ? [.noStoppingZone, .noParkingZone]
            : [.noParkingZone, .noStoppingZone]

        return DriveEvent(
            id: "",
            kind: .longStop,
            occurredAt: stop.start,
            coordinate: coordinate,
            roadName: zone.roadName,
            facts: facts,
            summary: summary,
            relatedTopicIDs: topics
        )
    }

    /// 좌표에 가장 가까운 금지구간과 그 거리(m).
    private func nearestZone(to coordinate: NaverCoordinate,
                             in zones: [EnforcementZone]) -> (EnforcementZone, Double)? {
        zones
            .map { ($0, $0.distance(from: coordinate)) }
            .min { $0.1 < $1.1 }
    }
}

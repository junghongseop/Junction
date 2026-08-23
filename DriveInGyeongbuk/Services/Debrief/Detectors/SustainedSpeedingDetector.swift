//
//  SustainedSpeedingDetector.swift
//  DriveInGyeongbuk
//
//  "제한속도를 넘긴 채로 얼마나 계속 달렸는가."
//
//  한 순간 튄 GPS 속도는 사건이 아니다. 일정 시간 이상 이어진 경우만 잡는다.
//  특히 중요한 건 **제한속도가 떨어진 직후에 이전 속도를 유지한 경우** — 외국인
//  운전자가 가장 자주 걸리는 상황이고, Debrief 가 설명해 줄 값어치가 가장 큰 지점이다.
//
//  ⚠️ 여기서 "위반"이라는 말을 쓰지 않는다. 우리가 아는 건 GPS 속도와 표준노드링크의
//     제한속도뿐이고, 둘 다 오차가 있다. 판정은 하지 않고 관측만 넘긴다.
//

import Foundation

nonisolated struct SustainedSpeedingDetector: DriveEventDetecting {

    /// 초과로 볼 허용 오차(km/h). `SpeedLimitService.toleranceKPH` 와 같은 취지다.
    var toleranceKPH = 5
    /// 이 시간 이상 이어져야 사건으로 본다(초).
    var minimumDurationSeconds: TimeInterval = 5
    /// 낮아진 구간에 들어선 뒤 이 거리 안에서 시작했으면 "변화 직후"로 본다(m).
    var afterDropDistanceMeters: Double = 400
    /// 한 주행에서 최대 몇 건까지 내놓을지. 초과폭이 큰 순으로 남긴다.
    var maximumEventCount = 3

    /// 샘플 하나에 그 자리의 제한속도 구간과 경로 진행거리를 붙인 것.
    private struct Annotated {
        var sample: DriveSample
        var segment: RouteSpeedLimitSegment
        /// 경로 출발점에서 이 샘플까지의 거리(m).
        var distanceFromStart: Double
    }

    func detect(in context: DriveEventContext) -> [DriveEvent] {

        guard let progress = context.progress,
              !context.speedLimitSegments.isEmpty else { return [] }

        progress.rewind()
        defer { progress.rewind() }

        // 1) 샘플마다 그 자리의 제한속도와 진행거리를 붙인다.
        //    시간순으로 훑기 때문에 색인 커서가 앞으로만 움직인다 (RouteProgressIndex 주석 참고).
        var annotated: [Annotated] = []
        for sample in context.recording.samples {
            guard let index = progress.index(for: sample.coordinate),
                  let segment = context.speedLimitSegments.last(where: { $0.startPathIndex <= index }),
                  segment.isReliableLimit,
                  let distance = progress.distanceFromStart(atIndex: index) else { continue }
            annotated.append(Annotated(sample: sample, segment: segment, distanceFromStart: distance))
        }

        // 2) 초과 상태가 이어지는 구간으로 묶는다.
        var runs: [[Annotated]] = []
        var current: [Annotated] = []

        for entry in annotated {
            guard let speed = entry.sample.speedKPH,
                  let limit = entry.segment.limitKPH,
                  speed > limit + toleranceKPH else {
                if !current.isEmpty { runs.append(current) }
                current = []
                continue
            }
            // 도로 링크가 달라도 제한속도가 같으면 연속 과속이다. 제한속도 자체가
            // 바뀌는 순간에만 별개의 사건으로 끊는다.
            if let previous = current.last,
               previous.segment.limitKPH != entry.segment.limitKPH {
                runs.append(current)
                current = []
            }
            current.append(entry)
        }
        if !current.isEmpty { runs.append(current) }

        // 3) 충분히 오래 이어진 것만 사건으로. 초과폭이 큰 것부터 추린 뒤 다시 시간순으로.
        let events = runs.compactMap { makeEvent(from: $0, context: context) }

        return Array(events.sorted { excess(of: $0) > excess(of: $1) }.prefix(maximumEventCount))
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    // MARK: -

    private func makeEvent(from run: [Annotated], context: DriveEventContext) -> DriveEvent? {

        guard let first = run.first, let last = run.last,
              let limit = first.segment.limitKPH else { return nil }

        let duration = last.sample.timestamp.timeIntervalSince(first.sample.timestamp)
        guard duration >= minimumDurationSeconds else { return nil }

        let speeds = run.compactMap(\.sample.speedKPH)
        guard let peak = speeds.max() else { return nil }
        let average = Int((Double(speeds.reduce(0, +)) / Double(speeds.count)).rounded())

        let previousLimit = previousSegmentLimit(before: first.segment, context: context)
        // 제한속도가 낮아진 구간이고, 그 구간에 들어선 지 얼마 안 돼 시작했는가.
        let metersIntoSegment = first.distanceFromStart - first.segment.distanceFromStartMeters
        let afterDrop = previousLimit.map { $0 > limit } == true
            && metersIntoSegment >= 0
            && metersIntoSegment <= afterDropDistanceMeters

        var facts: [DriveEvent.Fact] = [
            .init("speedLimitKPH", limit),
            .init("peakSpeedKPH", peak),
            .init("averageSpeedKPH", average),
            .init("durationSeconds", Int(duration.rounded())),
            .init("startedRightAfterLimitDrop", afterDrop)
        ]
        if let previousLimit {
            facts.append(.init("previousSpeedLimitKPH", previousLimit))
        }
        if afterDrop {
            facts.append(.init("metersAfterNewSignPost", Int(metersIntoSegment.rounded())))
        }
        if let roadName = first.segment.roadName, !roadName.isEmpty {
            facts.append(.init("roadName", roadName))
        }

        let seconds = Int(duration.rounded())
        let summary = afterDrop
            ? "Held about \(average) km/h for \(seconds) s just after the limit dropped to \(limit) km/h."
            : "Held about \(average) km/h for \(seconds) s where the limit was \(limit) km/h."

        // 제한속도 변화 직후였다면 "왜 그렇게 됐는지"부터 설명하는 게 맞다.
        let topics: [DebriefTopicID] = afterDrop
            ? [.speedLimitChange, .speedingRule, .trafficCamera]
            : [.speedingRule, .trafficCamera]

        return DriveEvent(
            id: "",   // 최종 ID 는 `DriveEventDetector` 가 시간순으로 매긴다.
            kind: .sustainedSpeeding,
            occurredAt: first.sample.timestamp,
            coordinate: first.sample.coordinate,
            roadName: first.segment.roadName,
            facts: facts,
            summary: summary,
            relatedTopicIDs: topics
        )
    }

    /// 경로상 바로 앞에 있던 신뢰할 만한 구간의 제한속도.
    private func previousSegmentLimit(before segment: RouteSpeedLimitSegment,
                                      context: DriveEventContext) -> Int? {
        context.speedLimitSegments
            .last { $0.startPathIndex < segment.startPathIndex && $0.isReliableLimit }?
            .limitKPH
    }

    private func excess(of event: DriveEvent) -> Int {
        let peak = event.fact("peakSpeedKPH").flatMap(Int.init) ?? 0
        let limit = event.fact("speedLimitKPH").flatMap(Int.init) ?? 0
        return peak - limit
    }
}

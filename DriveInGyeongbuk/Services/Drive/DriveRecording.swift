//
//  DriveRecording.swift
//  DriveInGyeongbuk
//
//  한 번의 주행을 통째로 담은 기록. Debrief 파이프라인 전체의 입력이다.
//
//      DriveRecording  →  DriveEventDetector  →  [DriveEvent]  →  LLM
//
//  `DrivingRoute` 가 "가려던 길"이라면 이쪽은 "실제로 간 길"이다. 둘 다 있어야
//  "제한속도가 바뀐 지점을 실제로 어떻게 통과했는가" 같은 판정이 된다.
//
//  경로 없이(자유 주행) 기록될 수도 있어서 `route` 는 옵셔널이다. 그 경우 경로에
//  기대는 감지기(톨게이트 등)는 조용히 아무것도 내놓지 않는다.
//

import Foundation

nonisolated struct DriveRecording: Identifiable, Hashable {

    var id = UUID()

    /// 주행에 쓴 탐색 경로. 자유 주행이면 `nil`.
    var route: DrivingRoute?
    /// 출발지 표기. 없으면 화면에서 생략한다.
    var originName: String?
    /// 목적지 표기.
    var destinationName: String?

    var startedAt: Date
    var endedAt: Date

    /// 시간순 위치 갱신. 비어 있을 수 있다(위치 권한 거부 등).
    var samples: [DriveSample]

    /// 이 사용자의 한국 첫 주행인지. 안내 우선순위와 헤드라인이 달라진다.
    var isFirstDriveInKorea: Bool

    init(id: UUID = UUID(),
         route: DrivingRoute? = nil,
         originName: String? = nil,
         destinationName: String? = nil,
         startedAt: Date,
         endedAt: Date,
         samples: [DriveSample],
         isFirstDriveInKorea: Bool = false) {
        self.id = id
        self.route = route
        self.originName = originName
        self.destinationName = destinationName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.samples = samples
        self.isFirstDriveInKorea = isFirstDriveInKorea
    }

    // MARK: - 파생 값

    /// 실제 주행 시간(초).
    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    /// 실제 이동 거리(m).
    ///
    /// 경로의 총 거리가 아니라 기록된 좌표를 이은 길이다. 중간에 이탈했거나
    /// 목적지 전에 끝냈으면 경로 거리와 다르다. 샘플이 부족하면 경로 거리로 물러선다.
    var distanceMeters: Double {
        guard samples.count >= 2 else { return route.map { Double($0.distance) } ?? 0 }
        var total = 0.0
        for index in 1..<samples.count {
            total += samples[index - 1].coordinate.distance(to: samples[index].coordinate)
        }
        return total
    }

    /// 기록된 최고 속도(km/h). 속도를 한 번도 못 받았으면 `nil`.
    var topSpeedKPH: Int? { samples.compactMap(\.speedKPH).max() }

    /// 사람이 읽는 거리 표기. Figma 헤드라인의 "· 32 km" 자리.
    var distanceDescription: String {
        distanceMeters >= 1000
            ? String(format: "%.0f km", distanceMeters / 1000)
            : "\(Int(distanceMeters.rounded())) m"
    }

    /// 사람이 읽는 소요 시간 표기.
    var durationDescription: String {
        let minutes = Int(duration / 60)
        if minutes >= 60 { return "\(minutes / 60) hr \(minutes % 60) min" }
        return "\(max(1, minutes)) min"
    }

    /// "Pohang → Gyeongju · 32 km" 형태의 한 줄 요약.
    var routeDescription: String {
        let places = [originName, destinationName].compactMap { $0 }
        let leg = places.count == 2 ? places.joined(separator: " → ") : places.first
        return [leg, distanceDescription].compactMap { $0 }.joined(separator: " · ")
    }

    /// 사건 판정에 쓸 만한 기록인지. 너무 짧으면 Debrief 를 띄우지 않는다.
    var isSubstantial: Bool {
        samples.count >= 5 && duration >= 60
    }

    // MARK: - 조회

    /// 주어진 시각 이후 `seconds` 초 동안의 샘플.
    func samples(from start: Date, seconds: TimeInterval) -> [DriveSample] {
        let end = start.addingTimeInterval(seconds)
        return samples.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    /// 좌표에서 `radiusMeters` 안에 들어온 첫 샘플.
    func firstSample(near coordinate: NaverCoordinate, radiusMeters: Double) -> DriveSample? {
        samples.first { $0.coordinate.distance(to: coordinate) <= radiusMeters }
    }
}

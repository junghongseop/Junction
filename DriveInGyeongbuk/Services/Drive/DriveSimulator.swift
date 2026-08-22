//
//  DriveSimulator.swift
//  DriveInGyeongbuk
//
//  [개발/데모 전용] 탐색된 경로를 따라 "달린 척" 하는 주행 기록을 만든다.
//
//  왜 필요한가
//    Debrief 를 확인하려면 실제로 차를 몰고 나가야 한다. 그래서는 감지 규칙 하나 고칠
//    때마다 도로에 나가야 한다. 이 시뮬레이터는 **실제와 같은 경로 · 같은 제한속도
//    데이터**를 쓰되 위치 갱신만 지어내서, 시뮬레이터 안에서 파이프라인 전체를 돌린다.
//
//    지어내는 것은 딱 하나, "어디를 언제 몇 km/h 로 지났는가"다. 그 뒤의 감지 · 주제
//    선정 · 설명은 실제 주행과 완전히 같은 코드를 탄다.
//
//  ⚠️ 제품 코드가 아니다. `Test/` 의 화면들처럼 출시 전에 걷어낼 대상이다.
//

import Foundation

nonisolated struct DriveSimulator {

    /// 위치 갱신 간격(초).
    var sampleIntervalSeconds: TimeInterval = 2
    /// 제한속도를 모르는 구간에서 낼 속도(km/h).
    var defaultSpeedKPH: Int = 60
    /// 제한속도 대비 얼마나 여유를 두고 달리는지(km/h). 실제 주행의 미세한 초과를 흉내 낸다.
    var cruiseMarginKPH: Int = -3

    /// 운전 습관. 어떤 사건이 감지될지가 이걸로 갈린다.
    enum Behaviour {
        /// 표지판을 잘 따라간다. 과속 사건이 안 생긴다.
        case attentive
        /// 제한속도가 떨어져도 한동안 이전 속도를 유지한다.
        /// 외국인 운전자가 실제로 가장 자주 겪는 상황이고, Debrief 가 겨냥하는 지점이다.
        case lateToSlowDown(metersLate: Double, overshootKPH: Int)
    }

    /// 도착 후 목적지에 세워 두는 시간(분). 0 이면 정차 사건이 안 생긴다.
    var parkingMinutesAtGoal: Int = 6

    // MARK: -

    /// - Parameters:
    ///   - route: 실제로 탐색된 경로.
    ///   - segments: `SpeedLimitService.prepare(for:)` 결과. 비어 있으면 기본 속도로 달린다.
    func simulate(route: DrivingRoute,
                  segments: [RouteSpeedLimitSegment],
                  behaviour: Behaviour = .lateToSlowDown(metersLate: 260, overshootKPH: 14),
                  startedAt: Date = .now,
                  originName: String? = nil,
                  destinationName: String? = nil,
                  isFirstDriveInKorea: Bool = true) -> DriveRecording {

        let path = route.path
        guard path.count >= 2 else {
            return DriveRecording(route: route,
                                  originName: originName,
                                  destinationName: destinationName,
                                  startedAt: startedAt,
                                  endedAt: startedAt,
                                  samples: [],
                                  isFirstDriveInKorea: isFirstDriveInKorea)
        }

        let cumulative = Self.cumulativeDistances(of: path)
        let total = cumulative.last ?? 0

        var samples: [DriveSample] = []
        var travelled = 0.0
        var elapsed: TimeInterval = 0

        while travelled < total {
            let index = Self.pathIndex(for: travelled, in: cumulative)
            let speedKPH = speed(atPathIndex: index,
                                 travelled: travelled,
                                 segments: segments,
                                 behaviour: behaviour)

            samples.append(DriveSample(
                coordinate: Self.interpolate(at: travelled, path: path, cumulative: cumulative),
                timestamp: startedAt.addingTimeInterval(elapsed),
                speedKPH: speedKPH,
                courseDegrees: nil
            ))

            travelled += Double(speedKPH) / 3.6 * sampleIntervalSeconds
            elapsed += sampleIntervalSeconds
        }

        // 도착 지점에 세워 둔다. 좌표를 조금씩 흔들어 실제 GPS 표류를 흉내 낸다.
        if parkingMinutesAtGoal > 0 {
            let parkingSeconds = TimeInterval(parkingMinutesAtGoal * 60)
            var parked: TimeInterval = 0
            var drift = 0
            while parked <= parkingSeconds {
                let jitter = Double(drift % 3 - 1) * 0.00004   // 대략 ±4m
                samples.append(DriveSample(
                    coordinate: NaverCoordinate(latitude: route.goal.latitude + jitter,
                                                longitude: route.goal.longitude - jitter),
                    timestamp: startedAt.addingTimeInterval(elapsed + parked),
                    speedKPH: 0,
                    courseDegrees: nil
                ))
                parked += 10
                drift += 1
            }
            elapsed += parkingSeconds
        }

        return DriveRecording(route: route,
                              originName: originName,
                              destinationName: destinationName,
                              startedAt: startedAt,
                              endedAt: startedAt.addingTimeInterval(elapsed),
                              samples: samples,
                              isFirstDriveInKorea: isFirstDriveInKorea)
    }

    // MARK: - 속도 만들기

    private func speed(atPathIndex index: Int,
                       travelled: Double,
                       segments: [RouteSpeedLimitSegment],
                       behaviour: Behaviour) -> Int {

        guard let segment = segments.last(where: { $0.startPathIndex <= index }),
              segment.isReliableLimit,
              let limit = segment.limitKPH else {
            return defaultSpeedKPH
        }

        let cruising = max(20, limit + cruiseMarginKPH)

        switch behaviour {
        case .attentive:
            return cruising

        case .lateToSlowDown(let metersLate, let overshootKPH):
            // 직전 구간의 제한속도가 더 높았고, 새 구간에 들어선 지 얼마 안 됐다면
            // 아직 이전 속도로 달리고 있다.
            let previousLimit = segments
                .last { $0.startPathIndex < segment.startPathIndex && $0.isReliableLimit }?
                .limitKPH
            let metersIntoSegment = travelled - segment.distanceFromStartMeters

            guard let previousLimit, previousLimit > limit,
                  metersIntoSegment >= 0, metersIntoSegment <= metersLate else {
                return cruising
            }
            return min(previousLimit, limit + overshootKPH)
        }
    }

    // MARK: - 경로 계산

    private static func cumulativeDistances(of path: [NaverCoordinate]) -> [Double] {
        var result: [Double] = [0]
        result.reserveCapacity(path.count)
        var total = 0.0
        for index in 1..<path.count {
            total += path[index - 1].distance(to: path[index])
            result.append(total)
        }
        return result
    }

    /// 누적 거리 배열에서 `distance` 가 속한 구간의 시작 인덱스.
    private static func pathIndex(for distance: Double, in cumulative: [Double]) -> Int {
        // 정렬된 배열이라 이분 탐색으로 찾는다. 샘플마다 부르기 때문에 선형 탐색이면 느리다.
        var low = 0
        var high = cumulative.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if cumulative[mid] <= distance { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// 출발점에서 `distance` 만큼 간 지점의 좌표.
    private static func interpolate(at distance: Double,
                                    path: [NaverCoordinate],
                                    cumulative: [Double]) -> NaverCoordinate {
        let index = pathIndex(for: distance, in: cumulative)
        guard index + 1 < path.count else { return path[path.count - 1] }

        let segmentLength = cumulative[index + 1] - cumulative[index]
        guard segmentLength > 0 else { return path[index] }

        let ratio = (distance - cumulative[index]) / segmentLength
        let from = path[index]
        let to = path[index + 1]
        return NaverCoordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * ratio,
            longitude: from.longitude + (to.longitude - from.longitude) * ratio
        )
    }
}

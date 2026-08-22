//
//  EnforcementService.swift
//  DriveInGyeongbuk
//
//  도착지 근처 주정차 단속 구간 안내.
//  "여기 세우면 과태료"를 도착 전에 미리 알려주는 것이 목적.
//
//  쓰는 법
//    let service = EnforcementService()
//    try await service.zones(near: route.goal, radiusMeters: 1000)   // 도착 전 1회
//    service.warnings(at: here)                                      // 위치 갱신마다
//
//  `zones` 는 네트워크를 타지만 `warnings` 는 캐시된 구간만 훑는 메모리 계산이라
//  위치가 갱신될 때마다 불러도 된다.
//

import Foundation

/// 사용자에게 띄울 단속 구간 경고.
nonisolated struct EnforcementWarning: Identifiable, Hashable {

    var id: String { zone.id }

    var zone: EnforcementZone
    /// 현재 위치에서의 거리(m).
    var distanceMeters: Int
    /// 지금 시각이 단속 시간대인지.
    var isCurrentlyEnforced: Bool
    /// 판정에 쓴 상태.
    var status: RestrictionStatus
    /// 한국어 안내 문구.
    var koreanMessage: String
    /// 외국어 안내 문구.
    var localizedMessage: String

    var distanceDescription: String {
        distanceMeters >= 1000
            ? String(format: "%.1f km", Double(distanceMeters) / 1000)
            : "\(distanceMeters) m"
    }
}

protocol EnforcementServicing {
    /// 도착지 근처 단속 구간을 가져온다.
    ///
    /// - Parameter radiusMeters: 서버 검색 반경(2km)보다 크게 넣어도 2km 로 잘린다.
    func zones(near destination: NaverCoordinate,
               radiusMeters: Int) async throws -> [EnforcementZone]

    /// 현재 위치 기준 경고를 만든다. 없으면 빈 배열.
    func warnings(at coordinate: NaverCoordinate, date: Date) -> [EnforcementWarning]
}

// MARK: -

final class EnforcementService: EnforcementServicing {

    /// 경고를 띄울 거리(m).
    var warningRadiusMeters: Int = 150

    /// 서버가 계산해 준 상태를 그대로 믿을 시간(초).
    ///
    /// 서버 상태는 공휴일까지 반영해서 가장 정확하지만 조회 시점의 값이다.
    /// 이 시간이 지나면 앱이 시간표로 다시 계산한다.
    /// (앱은 공휴일 목록이 없어 일요일만 공휴일로 본다 — `RestrictionSchedule.status(at:)` 참고)
    var serverStatusLifetime: TimeInterval = 300

    /// 같은 목적지를 다시 물어봤을 때 네트워크를 건너뛸 시간(초).
    ///
    /// 서버 상태를 믿는 시간과 같게 두었다. 이 시간이 지나면 어차피 앱이 시간표로
    /// 다시 계산해야 하므로, 그때는 서버에 새로 물어보는 편이 낫다.
    var cacheLifetime: TimeInterval = 300

    /// 목적지가 이 거리 안이면 같은 목적지로 본다(m).
    /// 서버 검색 반경이 2km 라 수십 m 차이로는 결과가 달라지지 않는다.
    private static let sameDestinationToleranceMeters: Double = 50

    private let apiClient: EnforcementAPIClientProtocol
    private(set) var cachedZones: [EnforcementZone] = []
    /// 캐시를 채운 시각. 서버 상태를 믿을지 판단하는 데 쓴다.
    private var cachedAt: Date?
    /// 캐시를 채울 때 쓴 목적지.
    private(set) var cachedDestination: NaverCoordinate?
    /// 캐시를 채울 때 쓴 반경(m). 더 넓게 물어보면 캐시를 쓸 수 없다.
    private var cachedRadiusMeters: Int = 0

    init(apiClient: EnforcementAPIClientProtocol = EnforcementAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: 조회

    @discardableResult
    func zones(near destination: NaverCoordinate,
               radiusMeters: Int = 1000) async throws -> [EnforcementZone] {

        // 서버 반경(2km)보다 넓게 요청해도 실제로 받은 만큼만 쓸 수 있다.
        let limit = min(max(radiusMeters, 0), JunctionServerConfiguration.fixedSearchRadiusMeters)

        // 방금 같은 목적지를 물어봤으면 그대로 돌려준다.
        //
        // 도착 임박에 한 번, 주행이 끝난 뒤 Debrief 에서 한 번 — 같은 목적지를 연달아
        // 두 번 묻는 흐름이 실제로 있다. 무료 호스팅이라 콜드 스타트가 수십 초 걸리는데,
        // 주행이 끝난 화면에서 그만큼 더 기다리게 할 이유가 없다.
        if canReuseCache(for: destination, radiusMeters: limit) {
            // 더 좁게 물어봤으면 캐시를 그만큼 잘라 준다. 캐시 자체는 넓은 쪽을 유지한다.
            return cachedZones.filter { $0.distanceFromDestinationMeters <= Double(limit) }
        }

        let fetched = try await apiClient.fetchEnforcementZones(around: destination)

        cachedZones = fetched
            .filter { $0.distanceFromDestinationMeters <= Double(limit) }
            .sorted { $0.distanceFromDestinationMeters < $1.distanceFromDestinationMeters }
        cachedAt = .now
        cachedDestination = destination
        cachedRadiusMeters = limit

        return cachedZones
    }

    /// 캐시를 비운다. 목적지를 바꾸면 호출한다.
    func clearCache() {
        cachedZones = []
        cachedAt = nil
        cachedDestination = nil
        cachedRadiusMeters = 0
    }

    /// 캐시를 그대로 써도 되는지.
    ///
    /// 캐시는 이미 그때의 반경으로 잘려 있다. 더 넓게 물어보면 잘려 나간 구간이
    /// 빠진 답을 주게 되므로 그때는 다시 받는다.
    private func canReuseCache(for destination: NaverCoordinate, radiusMeters: Int) -> Bool {
        guard let cachedAt, let cachedDestination,
              radiusMeters <= cachedRadiusMeters,
              Date().timeIntervalSince(cachedAt) < cacheLifetime,
              cachedDestination.distance(to: destination) <= Self.sameDestinationToleranceMeters
        else { return false }
        return true
    }

    // MARK: 경고

    /// 현재 위치 기준 경고 목록.
    ///
    /// 단속 시간대가 아닌 구간도 함께 돌려준다(`isCurrentlyEnforced == false`).
    /// "지금은 괜찮지만 8시부터 금지"를 보여 줘야 하기 때문이다.
    /// 지금 당장 위험한 것만 필요하면 `activeWarnings(at:date:)` 를 쓴다.
    func warnings(at coordinate: NaverCoordinate, date: Date = .now) -> [EnforcementWarning] {

        let radius = Double(warningRadiusMeters)
        // 캐시가 신선하면 서버가 공휴일까지 반영해 준 상태를 그대로 쓴다.
        let trustsServerStatus = cachedAt.map { date.timeIntervalSince($0) < serverStatusLifetime } ?? false

        return cachedZones
            .compactMap { zone -> EnforcementWarning? in
                let distance = zone.distance(from: coordinate)
                guard distance <= radius else { return nil }

                let status = trustsServerStatus ? zone.serverStatus : zone.schedule.status(at: date)
                let meters = Int(distance.rounded())

                return EnforcementWarning(
                    zone: zone,
                    distanceMeters: meters,
                    isCurrentlyEnforced: status.prohibitsParkingNow,
                    status: status,
                    koreanMessage: Self.koreanMessage(zone: zone, status: status, distanceMeters: meters),
                    localizedMessage: Self.englishMessage(zone: zone, status: status, distanceMeters: meters)
                )
            }
            // 지금 금지인 것을 먼저, 그다음 가까운 순.
            .sorted {
                $0.isCurrentlyEnforced == $1.isCurrentlyEnforced
                    ? $0.distanceMeters < $1.distanceMeters
                    : $0.isCurrentlyEnforced
            }
    }

    /// 지금 실제로 주정차가 금지된 구간만.
    func activeWarnings(at coordinate: NaverCoordinate, date: Date = .now) -> [EnforcementWarning] {
        warnings(at: coordinate, date: date).filter(\.isCurrentlyEnforced)
    }

    // MARK: - 안내 문구

    // TODO: `RoadSignExplanationService` 가 구현되면 다국어 문구를 그쪽으로 옮긴다.
    //       지금은 영어만, 이 파일에서 직접 만든다.

    private static func koreanMessage(zone: EnforcementZone,
                                      status: RestrictionStatus,
                                      distanceMeters: Int) -> String {
        let place = "\(zone.displayName) \(distanceMeters)m 앞"

        switch status {
        case .restricted:
            return "\(place) — 지금 주정차 금지 구간입니다. (\(zone.koreanTypeName))"
        case .temporarilyAllowed:
            return "\(place) — 주정차 금지 구간이지만 지금은 일시 허용 시간입니다."
        case .inactive:
            let hours = zone.schedule.summary
            return "\(place) — 지금은 단속 시간이 아닙니다. (금지 시간: \(hours))"
        }
    }

    /// 도로명은 번역할 수 없어 한국어를 그대로 둔다. 표지판과 대조해야 하므로 오히려 그편이 낫다.
    private static func englishMessage(zone: EnforcementZone,
                                       status: RestrictionStatus,
                                       distanceMeters: Int) -> String {
        let place = "\(zone.roadName) · \(distanceMeters) m ahead"

        switch status {
        case .restricted:
            return "\(place) — No parking or stopping here right now (\(zone.kind.englishName))."
        case .temporarilyAllowed:
            return "\(place) — Normally a no-parking zone, but parking is allowed at this hour."
        case .inactive:
            return "\(place) — Not enforced right now. Prohibited hours: \(zone.schedule.summary)."
        }
    }
}

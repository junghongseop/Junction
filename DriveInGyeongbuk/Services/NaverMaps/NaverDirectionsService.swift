//
//  NaverDirectionsService.swift
//  DriveInGyeongbuk
//
//  자동차 경로 탐색 (NAVER Cloud Platform > Maps > Directions 5).
//
//  이 서비스가 만들어 내는 `DrivingRoute` 가 나머지 안내 서비스들의 공통 입력이 된다.
//    - `route.sections`      → SpeedLimit  (도로별 제한속도 매칭)
//    - `route.steps`         → RoadSign    (한국어 안내 문구 해설)
//    - `route.tollGateSteps` → TollGate    (요금소에서 어느 차로로 갈지)
//    - `route.goal`          → Parking / Enforcement (도착지 주변 정보)
//

import Foundation

protocol NaverDirectionsServicing {
    /// 자동차 경로를 탐색한다.
    /// - Parameters:
    ///   - start: 출발지
    ///   - goal: 목적지
    ///   - waypoints: 경유지 (최대 5개)
    ///   - option: 탐색 옵션
    func route(from start: NaverCoordinate,
               to goal: NaverCoordinate,
               waypoints: [NaverCoordinate],
               option: RouteOption) async throws -> DrivingRoute

    /// 여러 옵션을 한 번에 요청해 비교용 경로 목록을 받는다.
    func routes(from start: NaverCoordinate,
                to goal: NaverCoordinate,
                waypoints: [NaverCoordinate],
                options: [RouteOption]) async throws -> [DrivingRoute]
}

extension NaverDirectionsServicing {
    func route(from start: NaverCoordinate,
               to goal: NaverCoordinate,
               option: RouteOption = .optimal) async throws -> DrivingRoute {
        try await route(from: start, to: goal, waypoints: [], option: option)
    }
}

// MARK: -

struct NaverDirectionsService: NaverDirectionsServicing {

    /// Directions 5 가 허용하는 최대 경유지 수.
    static let maxWaypointCount = 5

    private let runner: NaverMapsRequestRunner
    /// 지역 검색 좌표와 GPS 좌표를 실제 도로 중심선으로 보정할 때 사용한다.
    /// 번들 DB를 열 수 없거나 경북 밖이면 원래 좌표만으로 Directions를 요청한다.
    private let roadDataSource: (any SpeedLimitDataSource)?

    init(configuration: NaverMapsConfiguration = .default,
         httpClient: NaverMapsHTTPClient = URLSessionNaverMapsHTTPClient(),
         roadDataSource: (any SpeedLimitDataSource)? = nil) {
        self.runner = NaverMapsRequestRunner(configuration: configuration, httpClient: httpClient)
        self.roadDataSource = roadDataSource ?? (try? SQLiteSpeedLimitDataSource())
    }

    // MARK: 단일 경로

    func route(from start: NaverCoordinate,
               to goal: NaverCoordinate,
               waypoints: [NaverCoordinate] = [],
               option: RouteOption = .optimal) async throws -> DrivingRoute {

        let found = try await routes(from: start, to: goal, waypoints: waypoints, options: [option])
        guard let first = found.first else { throw NaverMapsError.emptyResult }
        return first
    }

    // MARK: 복수 옵션

    func routes(from start: NaverCoordinate,
                to goal: NaverCoordinate,
                waypoints: [NaverCoordinate] = [],
                options: [RouteOption] = [.optimal]) async throws -> [DrivingRoute] {

        guard !options.isEmpty else {
            throw NaverMapsError.invalidRequest("탐색 옵션이 비어 있습니다.")
        }
        guard waypoints.count <= Self.maxWaypointCount else {
            throw NaverMapsError.invalidRequest("경유지는 최대 \(Self.maxWaypointCount)개까지 지정할 수 있습니다.")
        }

        // 지역 검색 좌표는 건물·관광지 중심점, GPS는 주차장·건물 내부일 수 있다.
        // 임의의 반경 좌표는 실제 도로를 맞힌다는 보장이 없으므로 번들 도로 링크의
        // 중심선에 정확히 스냅한 좌표를 후보로 사용한다.
        async let snappedGoalsTask = roadCandidates(around: goal,
                                                     withinMeters: 1_000,
                                                     limit: 4,
                                                     preferNonMotorways: true)
        async let snappedStartsTask = roadCandidates(around: start,
                                                      withinMeters: 500,
                                                      limit: 4,
                                                      preferNonMotorways: false)
        let snappedGoals = await snappedGoalsTask
        let snappedStarts = await snappedStartsTask

        // 경북 도로 DB 밖의 장소도 검색되므로 전국 공통 폴백으로 주변 좌표를 단건 시도한다.
        // 실제 진입 도로 후보 → 장소 원본 → 가까운 반경 순서다.
        let fallbackGoals = Self.radialCandidates(around: goal, radiiMeters: [50, 120, 250])
        let fallbackStarts = Self.radialCandidates(around: start, radiiMeters: [40, 100])
        let goalCandidates = Self.uniqueCoordinates(snappedGoals + [goal] + fallbackGoals)
        let startCandidates = Self.uniqueCoordinates([start] + snappedStarts + fallbackStarts)
        let attempts = Self.routeAttempts(starts: startCandidates, goals: goalCandidates)

        for attempt in attempts {
            try Task.checkCancellation()
            do {
                return try await requestRoutes(from: attempt.start,
                                               goal: attempt.goal,
                                               originalGoal: goal,
                                               waypoints: waypoints,
                                               options: options)
            } catch let error where Self.isOffRoadError(error) {
                // 실제 API는 다중 목적지 중 하나만 도로 밖이어도 요청 전체를 code 2로 거절한다.
                // 따라서 후보를 한 쿼리에 묶지 않고 다음 단건 조합을 시도한다.
                continue
            }
        }

        throw NaverMapsError.api(
            code: "2",
            message: "현재 위치 또는 선택한 장소 주변에서 차량이 진입할 수 있는 도로를 찾지 못했습니다."
        )
    }

    private func requestRoutes(from start: NaverCoordinate,
                               goal: NaverCoordinate,
                               originalGoal: NaverCoordinate,
                               waypoints: [NaverCoordinate],
                               options: [RouteOption]) async throws -> [DrivingRoute] {
        var queryItems = [
            URLQueryItem(name: "start", value: start.apiQueryValue),
            URLQueryItem(name: "goal", value: goal.apiQueryValue),
            URLQueryItem(name: "option", value: options.map(\.rawValue).joined(separator: ":"))
        ]
        if !waypoints.isEmpty {
            let value = waypoints.map(\.apiQueryValue).joined(separator: "|")
            queryItems.append(URLQueryItem(name: "waypoints", value: value))
        }

        let request = try runner.makeRequest(host: runner.configuration.directionsHost,
                                             path: runner.configuration.directionsPath,
                                             queryItems: queryItems)
        let dto = try await runner.send(request, as: NaverDirectionsResponseDTO.self)

        guard dto.code == 0 else {
            throw NaverMapsError.api(code: String(dto.code),
                                     message: dto.message ?? "경로를 찾지 못했습니다.")
        }
        guard let routeDictionary = dto.route, !routeDictionary.isEmpty else {
            throw NaverMapsError.emptyResult
        }

        let results: [DrivingRoute] = options.compactMap { option in
            guard let routeDTO = routeDictionary[option.rawValue]?.first else { return nil }
            return Self.makeRoute(from: routeDTO,
                                  option: option,
                                  fallbackStart: start,
                                  fallbackGoal: originalGoal)
        }

        guard !results.isEmpty else { throw NaverMapsError.emptyResult }
        return results
    }

    /// 가장 가능성 높은 조합부터 시도한다. 실제 현위치 → 현위치의 도로 스냅 후보 순서다.
    private static func routeAttempts(starts: [NaverCoordinate],
                                      goals: [NaverCoordinate])
    -> [(start: NaverCoordinate, goal: NaverCoordinate)] {
        guard let originalStart = starts.first, let primaryGoal = goals.first else { return [] }

        var attempts = [(start: originalStart, goal: primaryGoal)]
        attempts += goals.dropFirst().map { (start: originalStart, goal: $0) }

        // 출발지까지 보정해야 하는 경우에는 가능성 높은 목적지 후보 9개까지만 조합한다.
        // 실제 현위치가 유효하면 위의 첫 묶음에서 이미 반환된다.
        for snappedStart in starts.dropFirst() {
            attempts += goals.prefix(9).map { (start: snappedStart, goal: $0) }
        }
        // 한 번의 사용자 선택이 과도한 API 호출로 이어지지 않도록 전체 재시도에 상한을 둔다.
        return Array(attempts.prefix(40))
    }

    private static func uniqueCoordinates(_ coordinates: [NaverCoordinate]) -> [NaverCoordinate] {
        var seen = Set<String>()
        return coordinates.filter { coordinate in
            let key = String(format: "%.6f,%.6f", coordinate.longitude, coordinate.latitude)
            return seen.insert(key).inserted
        }
    }

    /// 중심점에서 가까운 반경부터 8방향으로 만든 전국 공통 도로 탐색 후보.
    /// 다중 목적지로 묶지 않고 `routeAttempts`에서 반드시 단건으로 요청한다.
    private static func radialCandidates(around center: NaverCoordinate,
                                         radiiMeters: [Double]) -> [NaverCoordinate] {
        let metersPerLatitudeDegree = 111_320.0
        let latitudeRadians = center.latitude * .pi / 180
        let metersPerLongitudeDegree = max(1, metersPerLatitudeDegree * cos(latitudeRadians))

        return radiiMeters.flatMap { radius in
            stride(from: 0.0, to: 360.0, by: 45.0).map { bearing in
                let radians = bearing * .pi / 180
                let north = cos(radians) * radius
                let east = sin(radians) * radius
                return NaverCoordinate(
                    latitude: center.latitude + north / metersPerLatitudeDegree,
                    longitude: center.longitude + east / metersPerLongitudeDegree
                )
            }
        }
    }

    /// 좌표 주변의 실제 도로 링크를 거리순으로 정렬하고 중심선 위 좌표로 스냅한다.
    private func roadCandidates(around coordinate: NaverCoordinate,
                                withinMeters: Double,
                                limit: Int,
                                preferNonMotorways: Bool) async -> [NaverCoordinate] {
        guard let roadDataSource,
              let links = try? await roadDataSource.links(around: coordinate,
                                                           radiusMeters: withinMeters),
              !links.isEmpty else {
            return []
        }

        let projected = KoreaCoordinateConverter.project(coordinate)
        let matches = links.compactMap { link -> (coordinate: NaverCoordinate,
                                                  distance: Double,
                                                  isMotorway: Bool)? in
            guard let nearest = link.nearestPoint(to: projected),
                  nearest.distance <= withinMeters else { return nil }
            return (KoreaCoordinateConverter.unproject(nearest.snapped),
                    nearest.distance,
                    link.roadRank.isMotorway)
        }
        .sorted { lhs, rhs in
            if preferNonMotorways, lhs.isMotorway != rhs.isMotorway {
                return !lhs.isMotorway
            }
            return lhs.distance < rhs.distance
        }

        var seen = Set<String>()
        return matches.compactMap { match in
            // 같은 양방향 도로 링크가 동일한 중심선을 공유하는 경우 중복 후보를 제거한다.
            let key = String(format: "%.6f,%.6f",
                             match.coordinate.longitude,
                             match.coordinate.latitude)
            guard seen.insert(key).inserted else { return nil }
            return match.coordinate
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    private static func isOffRoadError(_ error: Error) -> Bool {
        guard let error = error as? NaverMapsError else { return false }
        switch error {
        case .api(let code, _):
            return code == "2"
        case .httpStatus(let status, let body):
            guard status == 400 else { return false }
            if let data = body.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(DirectionsErrorEnvelope.self, from: data) {
                return envelope.error?.code == 2
            }
            return body.contains("\"code\":2")
        default:
            return false
        }
    }

    private struct DirectionsErrorEnvelope: Decodable {
        var error: Detail?

        struct Detail: Decodable {
            var code: Int?
            var message: String?
        }
    }

    // MARK: - Mapping

    private static func makeRoute(from dto: NaverDirectionsResponseDTO.RouteDTO,
                                  option: RouteOption,
                                  fallbackStart: NaverCoordinate,
                                  fallbackGoal: NaverCoordinate) -> DrivingRoute {

        let path = (dto.path ?? []).compactMap(NaverCoordinate.init(xyPair:))

        let sections = (dto.section ?? []).map { section in
            RouteSection(pointIndex: section.pointIndex ?? 0,
                         pointCount: section.pointCount ?? 0,
                         distance: section.distance ?? 0,
                         name: section.name ?? "",
                         congestion: section.congestion ?? 0,
                         currentSpeed: section.speed ?? 0)
        }

        let steps = makeSteps(from: dto.guide ?? [], path: path)

        let summary = dto.summary
        let start = makeCoordinate(summary.start?.location) ?? path.first ?? fallbackStart
        let goal = makeCoordinate(summary.goal?.location) ?? path.last ?? fallbackGoal

        return DrivingRoute(
            option: option,
            start: start,
            goal: goal,
            path: path,
            sections: sections,
            steps: steps,
            bounds: makeBounds(summary.bbox),
            distance: summary.distance ?? 0,
            // 네이버는 소요 시간을 밀리초로 준다. 앱 내부에서는 초로 통일한다.
            duration: (summary.duration ?? 0) / 1000,
            tollFare: summary.tollFare ?? 0,
            taxiFare: summary.taxiFare ?? 0,
            fuelPrice: summary.fuelPrice ?? 0
        )
    }

    private static func makeBounds(_ bbox: [[Double]]?) -> NaverCoordinateBounds? {
        guard let bbox else { return nil }
        return NaverCoordinateBounds(bbox: bbox)
    }

    /// `[경도, 위도]` 배열(옵셔널)을 좌표로.
    private static func makeCoordinate(_ xyPair: [Double]?) -> NaverCoordinate? {
        guard let xyPair else { return nil }
        return NaverCoordinate(xyPair: xyPair)
    }

    private static func makeSteps(from guides: [NaverDirectionsResponseDTO.GuideDTO],
                                  path: [NaverCoordinate]) -> [RouteStep] {

        var cumulativeDistance = 0

        return guides.compactMap { guide -> RouteStep? in
            let pointIndex = guide.pointIndex ?? 0
            guard path.indices.contains(pointIndex) else { return nil }

            let instructions = guide.instructions ?? ""
            let step = RouteStep(
                pointIndex: pointIndex,
                coordinate: path[pointIndex],
                distance: guide.distance ?? 0,
                duration: (guide.duration ?? 0) / 1000,
                instructions: instructions,
                rawType: guide.type ?? 0,
                kind: RouteGuideKind.classify(instructions: instructions),
                distanceFromStart: cumulativeDistance
            )

            // `guide.distance` 는 "이 안내 지점부터 다음 안내 지점까지"의 거리다.
            cumulativeDistance += guide.distance ?? 0
            return step
        }
    }
}

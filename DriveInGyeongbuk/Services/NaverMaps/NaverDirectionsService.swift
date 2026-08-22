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

    init(configuration: NaverMapsConfiguration = .default,
         httpClient: NaverMapsHTTPClient = URLSessionNaverMapsHTTPClient()) {
        self.runner = NaverMapsRequestRunner(configuration: configuration, httpClient: httpClient)
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

        // Directions 5 는 HTTP 200 이어도 code != 0 이면 실패다.
        guard dto.code == 0 else {
            throw NaverMapsError.api(code: String(dto.code),
                                     message: dto.message ?? "경로를 찾지 못했습니다.")
        }
        guard let routeDictionary = dto.route, !routeDictionary.isEmpty else {
            throw NaverMapsError.emptyResult
        }

        // 요청한 옵션 순서를 유지해 돌려준다.
        let results: [DrivingRoute] = options.compactMap { option in
            guard let routeDTO = routeDictionary[option.rawValue]?.first else { return nil }
            return Self.makeRoute(from: routeDTO, option: option, fallbackStart: start, fallbackGoal: goal)
        }

        guard !results.isEmpty else { throw NaverMapsError.emptyResult }
        return results
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

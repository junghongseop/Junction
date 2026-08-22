//
//  NaverMapsTestViewModel.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] Services/NaverMaps 의 세 파일이 제대로 동작하는지 확인하는 화면의 상태.
//

import Combine
import Foundation

final class NaverMapsTestViewModel: ObservableObject {

    // MARK: 입력

    @Published var startQuery: String = "경상북도 경주시 원화로 266"      // 경주역
    @Published var goalQuery: String = "경상북도 경주시 불국로 385"       // 불국사
    @Published var option: RouteOption = .optimal

    // MARK: 출력

    @Published private(set) var startPlace: GeocodedPlace?
    @Published private(set) var goalPlace: GeocodedPlace?
    @Published private(set) var geocodeResults: [GeocodedPlace] = []
    @Published private(set) var locationResults: [NaverLocation] = []
    @Published private(set) var route: DrivingRoute?
    @Published private(set) var tappedAddress: ReverseGeocodedAddress?

    @Published private(set) var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// 지도 제어용.
    let map = NaverMapWebController()

    private let geocodingService: NaverGeocodingServicing
    private let locationSearchService: NaverLocationSearchServicing
    private let directionsService: NaverDirectionsServicing

    init(geocodingService: NaverGeocodingServicing = NaverGeocodingService(),
         locationSearchService: NaverLocationSearchServicing = NaverLocationSearchService(),
         directionsService: NaverDirectionsServicing = NaverDirectionsService()) {
        self.geocodingService = geocodingService
        self.locationSearchService = locationSearchService
        self.directionsService = directionsService

        // 지도를 탭하면 곧바로 역지오코딩해서 주소를 보여 준다.
        map.onMapTap = { [weak self] coordinate in
            guard let self else { return }
            Task { await self.reverseGeocode(at: coordinate) }
        }
    }

    /// REST 키가 없으면 안내 문구를 돌려준다.
    var credentialWarning: String? {
        if !AppConfig.hasNaverMapClientID {
            return "Client ID 가 없어 지도가 표시되지 않습니다. Config/Config.xcconfig 를 설정해 주세요."
        }
        if !AppConfig.hasNaverMapsRESTCredentials {
            return "Client Secret 이 없어 주소 검색/경로 탐색이 동작하지 않습니다."
        }
        if !AppConfig.hasNaverSearchCredentials {
            return "검색 API 키가 없어 장소명 도착지 검색이 동작하지 않습니다. Naver_Search_Client_ID/Secret을 설정해 주세요."
        }
        return nil
    }

    // MARK: - Geocoding

    enum Endpoint {
        case start
        case goal

        var title: String {
            switch self {
            case .start: return "출발지"
            case .goal: return "도착지"
            }
        }
    }

    /// 출발지는 주소 지오코딩, 도착지는 업체/기관명 지역 검색을 사용한다.
    func search(_ endpoint: Endpoint) async {
        let query = endpoint == .start ? startQuery : goalQuery
        await run(status: "\(endpoint.title)을 검색하는 중…") {
            switch endpoint {
            case .start:
                let places = try await self.geocodingService.geocode(query: query, near: nil, limit: 10)
                self.locationResults = []
                self.geocodeResults = places
                if let first = places.first { self.select(first, as: .start) }
                self.statusMessage = "출발지 주소 검색 결과 \(places.count)건"
            case .goal:
                let locations = try await self.locationSearchService.search(query: query, display: 5)
                self.geocodeResults = []
                self.locationResults = locations
                if let first = locations.first { self.select(first) }
                self.statusMessage = "도착지 장소 검색 결과 \(locations.count)건"
            }
        }
    }

    func select(_ location: NaverLocation) {
        goalQuery = location.title
        select(location.geocodedPlace, as: .goal)
    }

    /// 검색 결과 중 하나를 출발지/도착지로 지정한다.
    func select(_ place: GeocodedPlace, as endpoint: Endpoint) {
        switch endpoint {
        case .start: startPlace = place
        case .goal: goalPlace = place
        }
        drawEndpointMarkers()
        map.focus(on: place.coordinate)
    }

    /// 좌표 → 주소. 지도를 탭했을 때 호출한다.
    func reverseGeocode(at coordinate: NaverCoordinate) async {
        await run(status: "탭한 지점의 주소를 찾는 중…") {
            let address = try await self.geocodingService.reverseGeocode(coordinate: coordinate)
            self.tappedAddress = address
            self.statusMessage = "탭한 지점: \(address.displayAddress)"
        }
    }

    // MARK: - Directions

    /// 출발지/도착지가 아직 없으면 먼저 지오코딩한 뒤 경로를 탐색한다.
    func findRoute() async {
        await run(status: "경로를 탐색하는 중…") {
            if self.startPlace == nil {
                self.startPlace = try await self.geocodingService.firstPlace(matching: self.startQuery)
            }
            if self.goalPlace == nil {
                let results = try await self.locationSearchService.search(query: self.goalQuery, display: 1)
                guard let first = results.first else { throw NaverLocationSearchError.emptyResult }
                self.goalPlace = first.geocodedPlace
            }
            guard let start = self.startPlace, let goal = self.goalPlace else {
                throw NaverMapsError.emptyResult
            }

            let route = try await self.directionsService.route(from: start.coordinate,
                                                               to: goal.coordinate,
                                                               waypoints: [],
                                                               option: self.option)
            self.route = route
            self.geocodeResults = []
            self.locationResults = []
            self.map.showRoute(route)
            self.statusMessage = """
            \(self.option.koreanTitle) · \(route.distanceDescription) · \(route.durationDescription) \
            · 안내 \(route.steps.count)개
            """
        }
    }

    /// 안내 스텝을 지도에서 강조한다.
    func focus(on step: RouteStep) {
        map.highlight(step.coordinate, label: step.instructions)
    }

    /// 경로를 다시 전체 보기로.
    func showWholeRoute() {
        guard let route else { return }
        map.showRoute(route)
    }

    func reset() {
        startPlace = nil
        goalPlace = nil
        geocodeResults = []
        locationResults = []
        route = nil
        tappedAddress = nil
        statusMessage = nil
        errorMessage = nil
        map.clear()
    }

    // MARK: - 내부

    private func drawEndpointMarkers() {
        var markers: [NaverMapWebController.Marker] = []
        if let startPlace {
            markers.append(.init(coordinate: startPlace.coordinate, title: "출발", color: "#1B8A4B"))
        }
        if let goalPlace {
            markers.append(.init(coordinate: goalPlace.coordinate, title: "도착", color: "#D1345B"))
        }
        guard !markers.isEmpty else { return }
        map.showMarkers(markers)
    }

    /// 로딩/에러 처리를 한 곳에 모은다.
    private func run(status: String, _ work: () async throws -> Void) async {
        isLoading = true
        statusMessage = status
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await work()
        } catch {
            statusMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

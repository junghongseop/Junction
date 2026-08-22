//
//  SpeedLimitTestViewModel.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] Services/SpeedLimit 이 제대로 동작하는지 확인하는 화면의 상태.
//
//  두 가지를 따로 확인한다.
//    1. 좌표 조회  — 번들 DB 만 쓰므로 네이버 API 키 없이도 동작한다.
//    2. 경로 구간  — Directions 5 로 경로를 받아야 하므로 REST 키가 필요하다.
//

import Combine
import Foundation

final class SpeedLimitTestViewModel: ObservableObject {

    /// 미리 넣어 둔 확인용 좌표.
    struct Preset: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var coordinate: NaverCoordinate
    }

    /// 도로 위 좌표를 골라 뒀다. (링크 중점을 그대로 쓴 값이라 매칭이 확실히 된다)
    ///
    /// 시청·관광지 같은 건물 좌표는 도로에서 70~100m 떨어져 있어 일부러 뺐다.
    /// 매칭 허용 거리(기본 35m) 밖이라 "매칭 없음"이 정상 동작인데 오해하기 쉽다.
    static let presets: [Preset] = [
        .init(name: "경주 원화로 50", coordinate: .init(latitude: 35.831335, longitude: 129.229361)),
        .init(name: "포항 새천년대로 80", coordinate: .init(latitude: 36.000001, longitude: 129.311512)),
        .init(name: "안동 퇴계로 30", coordinate: .init(latitude: 36.568749, longitude: 128.731243)),
        .init(name: "경부고속도로 100", coordinate: .init(latitude: 35.873764, longitude: 128.758674)),
        .init(name: "경주 불국로 40", coordinate: .init(latitude: 35.762681, longitude: 129.364097)),
        .init(name: "서울시청(범위 밖)", coordinate: .init(latitude: 37.5665, longitude: 126.9780))
    ]

    // MARK: 입력

    @Published var latitudeText = "35.8562"
    @Published var longitudeText = "129.2247"
    @Published var radiusMeters: Double = 300

    @Published var startQuery = "경상북도 경주시 원화로 266"      // 경주역
    @Published var goalQuery = "경상북도 경주시 불국로 385"       // 불국사

    /// 시뮬레이션 주행 속도(km/h).
    @Published var simulatedSpeedKPH: Double = 60 {
        didSet { updateSimulation() }
    }
    /// 경로 상의 진행 위치(0~1).
    @Published var simulationProgress: Double = 0 {
        didSet { updateSimulation() }
    }

    // MARK: 출력

    @Published private(set) var nearbyLinks: [SpeedLimitLink] = []
    @Published private(set) var nearestMatch: SpeedLimitMatch?

    @Published private(set) var route: DrivingRoute?
    @Published private(set) var segments: [RouteSpeedLimitSegment] = []

    @Published private(set) var simulatedCoordinate: NaverCoordinate?
    @Published private(set) var simulatedLimitKPH: Int?
    @Published private(set) var simulatedAlert: SpeedLimitAlert?

    @Published private(set) var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// 지도 제어용. 키가 없으면 지도는 안 뜨지만 나머지 기능은 그대로 동작한다.
    let map = NaverMapWebController()

    // MARK: 의존성

    private let dataSource: SpeedLimitDataSource?
    private let speedLimitService: SpeedLimitService?
    private let directionsService: NaverDirectionsServicing
    private let geocodingService: NaverGeocodingServicing

    /// DB 를 여는 데 실패했다면 그 사유.
    private(set) var setupError: String?

    init(directionsService: NaverDirectionsServicing = NaverDirectionsService(),
         geocodingService: NaverGeocodingServicing = NaverGeocodingService()) {
        self.directionsService = directionsService
        self.geocodingService = geocodingService

        // 데이터 소스 하나를 서비스와 나눠 쓴다. (DI 컨벤션 그대로)
        do {
            let source = try SQLiteSpeedLimitDataSource()
            self.dataSource = source
            self.speedLimitService = SpeedLimitService(dataSource: source)
        } catch {
            self.dataSource = nil
            self.speedLimitService = nil
            self.setupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        map.onMapTap = { [weak self] coordinate in
            guard let self else { return }
            self.latitudeText = String(format: "%.6f", coordinate.latitude)
            self.longitudeText = String(format: "%.6f", coordinate.longitude)
            Task { await self.lookupAroundTypedCoordinate() }
        }
    }

    /// REST 키가 없으면 경로 탐색 기능은 못 쓴다.
    var credentialWarning: String? {
        if !AppConfig.hasNaverMapsRESTCredentials {
            return "REST 키가 없어 '경로 제한속도' 섹션은 동작하지 않습니다. 좌표 조회는 번들 DB만 쓰므로 그대로 확인할 수 있습니다."
        }
        return nil
    }

    // MARK: - 1. 좌표 조회

    func use(_ preset: Preset) {
        latitudeText = String(format: "%.6f", preset.coordinate.latitude)
        longitudeText = String(format: "%.6f", preset.coordinate.longitude)
        Task { await lookupAroundTypedCoordinate() }
    }

    /// 입력한 좌표 주변의 링크를 조회하고 가장 가까운 링크를 매칭한다.
    func lookupAroundTypedCoordinate() async {
        guard let dataSource else {
            errorMessage = setupError
            return
        }
        guard let coordinate = typedCoordinate else {
            errorMessage = "좌표 형식이 올바르지 않습니다."
            return
        }

        await run(status: "주변 도로를 조회하는 중…") {
            guard KoreaCoordinateConverter.isInsideDataset(coordinate) else {
                self.nearbyLinks = []
                self.nearestMatch = nil
                throw SpeedLimitError.outsideCoverage
            }

            let links = try await dataSource.links(around: coordinate, radiusMeters: self.radiusMeters)
            // 가까운 순으로 보여 준다.
            let point = KoreaCoordinateConverter.project(coordinate)
            self.nearbyLinks = links.sorted {
                ($0.nearestPoint(to: point)?.distance ?? .greatestFiniteMagnitude)
                    < ($1.nearestPoint(to: point)?.distance ?? .greatestFiniteMagnitude)
            }
            self.nearestMatch = try await dataSource.nearestLink(to: coordinate, withinMeters: 40)

            self.showLookupOnMap(coordinate: coordinate)

            if let match = self.nearestMatch {
                self.statusMessage = """
                반경 \(Int(self.radiusMeters))m 안 링크 \(links.count)개 · \
                최근접 \(match.link.displayName) \(match.limitKPH)km/h \
                (\(Int(match.lateralDistanceMeters))m)
                """
            } else {
                self.statusMessage = "반경 \(Int(self.radiusMeters))m 안 링크 \(links.count)개 · 40m 안에 매칭된 도로 없음"
            }
        }
    }

    // MARK: - 2. 경로 제한속도 구간

    /// 출발지·도착지를 지오코딩해 경로를 받고, 제한속도 구간으로 쪼갠다.
    func findRouteAndPrepare() async {
        guard let speedLimitService else {
            errorMessage = setupError
            return
        }

        await run(status: "경로를 탐색하고 제한속도를 매칭하는 중…") {
            let start = try await self.geocodingService.firstPlace(matching: self.startQuery)
            let goal = try await self.geocodingService.firstPlace(matching: self.goalQuery)

            let route = try await self.directionsService.route(from: start.coordinate,
                                                               to: goal.coordinate,
                                                               waypoints: [],
                                                               option: .optimal)
            self.route = route
            self.map.showRoute(route)

            try await speedLimitService.prepare(for: route)
            self.segments = speedLimitService.routeSegments

            self.simulationProgress = 0
            self.updateSimulation()

            let matched = self.segments.filter { $0.limitKPH != nil }
            let matchedLength = matched.reduce(0) { $0 + $1.lengthMeters }
            let coverage = route.distance > 0 ? matchedLength / Double(route.distance) * 100 : 0

            self.statusMessage = String(
                format: "%@ · 구간 %d개 (제한속도 확인 %d개) · 커버리지 %.0f%%",
                route.distanceDescription, self.segments.count, matched.count, coverage
            )
        }
    }

    /// 슬라이더 위치를 경로 상의 좌표로 바꿔 안내를 만든다.
    func updateSimulation() {
        guard let speedLimitService, let route, !route.path.isEmpty else {
            simulatedCoordinate = nil
            simulatedLimitKPH = nil
            simulatedAlert = nil
            return
        }

        let index = min(route.path.count - 1,
                        max(0, Int((Double(route.path.count - 1) * simulationProgress).rounded())))
        let coordinate = route.path[index]
        let speed = Int(simulatedSpeedKPH.rounded())

        simulatedCoordinate = coordinate
        simulatedLimitKPH = speedLimitService.currentLimitKPH(at: coordinate)
        simulatedAlert = speedLimitService.alert(at: coordinate, speedKPH: speed)

        map.highlight(coordinate, label: simulatedLimitKPH.map { "제한 \($0)km/h" } ?? "제한속도 정보 없음")
    }

    // MARK: - 공통

    func reset() {
        nearbyLinks = []
        nearestMatch = nil
        route = nil
        segments = []
        simulatedCoordinate = nil
        simulatedLimitKPH = nil
        simulatedAlert = nil
        statusMessage = nil
        errorMessage = nil
        map.clear()
    }

    var typedCoordinate: NaverCoordinate? {
        guard let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
              let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return NaverCoordinate(latitude: latitude, longitude: longitude)
    }

    // MARK: 내부

    private func showLookupOnMap(coordinate: NaverCoordinate) {
        var markers: [NaverMapWebController.Marker] = [
            .init(coordinate: coordinate, title: "조회 지점", color: "#1B6AC6")
        ]
        if let nearestMatch {
            markers.append(.init(coordinate: nearestMatch.snappedCoordinate,
                                 title: "\(nearestMatch.limitKPH)km/h",
                                 color: "#D1345B"))
        }
        map.showMarkers(markers)
    }

    /// 로딩/에러 처리를 한 곳에 모은다. (NaverMapsTestViewModel 과 같은 패턴)
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

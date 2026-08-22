//
//  ParkingTestViewModel.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] Services/Parking + Services/Enforcement 검증 화면의 상태.
//
//  두 서비스 모두 Junction 백엔드(https://junction-server.onrender.com)만 쓰므로
//  네이버 API 키가 없어도 조회는 동작한다. (지도 표시에만 키가 필요하다)
//  주소로 목적지를 찾는 기능만 네이버 Geocoding 을 쓴다.
//

import Combine
import Foundation

final class ParkingTestViewModel: ObservableObject {

    /// 미리 넣어 둔 확인용 목적지.
    struct Preset: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var coordinate: NaverCoordinate
    }

    /// 주차장은 어디든 잘 나오지만, 주정차 금지구역은 원본 데이터가 있는 시군에서만 나온다.
    /// (서버가 "A ~ B" 형식으로 구간이 분명한 레코드만 처리하기 때문에 결과가 0건인 곳도 많다)
    static let presets: [Preset] = [
        .init(name: "포항시청", coordinate: .init(latitude: 36.019, longitude: 129.3435)),
        .init(name: "안동 옥동", coordinate: .init(latitude: 36.5684, longitude: 128.7294)),
        .init(name: "경주 황리단길", coordinate: .init(latitude: 35.8380, longitude: 129.2100)),
        .init(name: "구미역", coordinate: .init(latitude: 36.1289, longitude: 128.3300)),
        .init(name: "서울시청(범위 밖)", coordinate: .init(latitude: 37.5665, longitude: 126.9780))
    ]

    // MARK: 입력

    @Published var latitudeText = "36.019"
    @Published var longitudeText = "129.3435"
    /// 조회 반경(m). 서버는 2km 고정이라 그 이상은 의미가 없다.
    @Published var radiusMeters: Double = 2000
    /// 목적지를 주소로 찾을 때 쓰는 검색어.
    @Published var destinationQuery = "경상북도 포항시 남구 시청로 1"

    /// 경고 판정에 쓸 현재 위치를 구간 위로 옮겨 보기 위한 슬라이더(0~1).
    @Published var simulationProgress: Double = 0 {
        didSet { updateWarnings() }
    }

    // MARK: 출력

    @Published private(set) var destination: NaverCoordinate?
    @Published private(set) var suggestions: [ParkingSuggestion] = []
    @Published private(set) var zones: [EnforcementZone] = []
    @Published private(set) var warnings: [EnforcementWarning] = []
    @Published private(set) var simulatedCoordinate: NaverCoordinate?

    @Published private(set) var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// 지도 제어용. 키가 없으면 지도는 안 뜨지만 나머지 기능은 그대로 동작한다.
    let map = NaverMapWebController()

    // MARK: 의존성

    private let parkingService: ParkingService
    private let enforcementService: EnforcementService
    private let geocodingService: NaverGeocodingServicing

    init(parkingService: ParkingService = ParkingService(),
         enforcementService: EnforcementService = EnforcementService(),
         geocodingService: NaverGeocodingServicing = NaverGeocodingService()) {
        self.parkingService = parkingService
        self.enforcementService = enforcementService
        self.geocodingService = geocodingService

        map.onMapTap = { [weak self] coordinate in
            guard let self else { return }
            self.latitudeText = String(format: "%.6f", coordinate.latitude)
            self.longitudeText = String(format: "%.6f", coordinate.longitude)
            Task { await self.lookupAroundTypedCoordinate() }
        }
    }

    /// REST 키가 없으면 주소 검색만 못 쓴다.
    var credentialWarning: String? {
        if !AppConfig.hasNaverMapsRESTCredentials {
            return "REST 키가 없어 '주소로 목적지 찾기'는 동작하지 않습니다. 좌표 조회는 백엔드만 쓰므로 그대로 확인할 수 있습니다."
        }
        return nil
    }

    /// 경고 반경(m). 화면 표시용.
    var warningRadiusMeters: Int { enforcementService.warningRadiusMeters }

    // MARK: - 1. 좌표로 조회

    func use(_ preset: Preset) {
        latitudeText = String(format: "%.6f", preset.coordinate.latitude)
        longitudeText = String(format: "%.6f", preset.coordinate.longitude)
        Task { await lookupAroundTypedCoordinate() }
    }

    /// 입력한 좌표를 목적지로 삼아 주차장과 주정차 금지구역을 함께 조회한다.
    func lookupAroundTypedCoordinate() async {
        guard let coordinate = typedCoordinate else {
            errorMessage = "좌표 형식이 올바르지 않습니다."
            return
        }
        await lookup(destination: coordinate)
    }

    /// 주소를 지오코딩해 목적지로 삼는다.
    func lookupByAddress() async {
        await run(status: "주소를 찾는 중…") {
            let place = try await self.geocodingService.firstPlace(matching: self.destinationQuery)
            self.latitudeText = String(format: "%.6f", place.coordinate.latitude)
            self.longitudeText = String(format: "%.6f", place.coordinate.longitude)
            try await self.performLookup(destination: place.coordinate)
        }
    }

    private func lookup(destination coordinate: NaverCoordinate) async {
        await run(status: "주차장과 주정차 금지구역을 조회하는 중… (서버가 깨어나는 데 시간이 걸릴 수 있습니다)") {
            try await self.performLookup(destination: coordinate)
        }
    }

    /// 두 서비스를 **동시에** 호출한다. 서버가 요청마다 지도 API 를 타서 느리기 때문이다.
    private func performLookup(destination coordinate: NaverCoordinate) async throws {
        destination = coordinate
        // 목적지가 바뀌었으니 이전 캐시는 버린다.
        parkingService.clearCache()
        enforcementService.clearCache()

        let radius = Int(radiusMeters.rounded())

        async let lots = parkingService.suggestions(near: coordinate, radiusMeters: radius)
        async let restrictions = enforcementService.zones(near: coordinate, radiusMeters: radius)

        let (fetchedLots, fetchedZones) = try await (lots, restrictions)

        suggestions = fetchedLots
        zones = fetchedZones

        simulationProgress = 0
        updateWarnings()
        showOnMap()

        let enforcedNow = zones.filter { $0.serverStatus.prohibitsParkingNow }.count
        statusMessage = """
        주차장 \(suggestions.count)곳 · 주정차 금지구역 \(zones.count)곳 \
        (지금 단속 중 \(enforcedNow)곳) · 반경 \(radius)m
        """
    }

    // MARK: - 2. 경고 시뮬레이션

    /// 슬라이더 위치를 첫 번째 금지구간 위의 좌표로 바꿔 경고를 만들어 본다.
    ///
    /// 실제 주행에서는 이 자리에 GPS 좌표가 들어간다.
    func updateWarnings() {
        guard let zone = zones.first, !zone.path.isEmpty else {
            simulatedCoordinate = destination
            warnings = destination.map { enforcementService.warnings(at: $0) } ?? []
            return
        }

        let index = min(zone.path.count - 1,
                        max(0, Int((Double(zone.path.count - 1) * simulationProgress).rounded())))
        let coordinate = zone.path[index]

        simulatedCoordinate = coordinate
        warnings = enforcementService.warnings(at: coordinate)

        map.highlight(coordinate, label: warnings.first?.status.koreanName ?? "경고 없음")
    }

    // MARK: - 공통

    func reset() {
        destination = nil
        suggestions = []
        zones = []
        warnings = []
        simulatedCoordinate = nil
        statusMessage = nil
        errorMessage = nil
        parkingService.clearCache()
        enforcementService.clearCache()
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

    /// 목적지 · 주차장 · 금지구간을 한 번에 그린다.
    private func showOnMap() {
        guard let destination else { return }

        var markers: [NaverMapWebController.Marker] = [
            .init(coordinate: destination, title: "목적지", color: "#1B6AC6")
        ]
        // 마커가 너무 많으면 지도가 읽히지 않는다. 가까운 순 15곳만.
        markers += suggestions.prefix(15).map {
            .init(coordinate: $0.lot.coordinate, title: "P \($0.distanceDescription)", color: "#1B8A4B")
        }

        let polylines: [NaverMapWebController.Polyline] = zones.map { zone in
            .init(coordinates: zone.path,
                  color: zone.serverStatus.prohibitsParkingNow ? "#D1345B" : "#F5A524",
                  width: 6)
        }
        // 좌표가 하나뿐이라 선으로 못 그리는 구간은 마커로 대신 표시한다.
        markers += zones.filter { $0.path.count < 2 }.compactMap { zone in
            zone.path.first.map {
                .init(coordinate: $0,
                      title: zone.roadName,
                      color: zone.serverStatus.prohibitsParkingNow ? "#D1345B" : "#F5A524")
            }
        }

        map.showOverlays(polylines: polylines, markers: markers)
    }

    /// 로딩/에러 처리를 한 곳에 모은다. (SpeedLimitTestViewModel 과 같은 패턴)
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

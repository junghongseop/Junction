//
//  MapHomeViewModel.swift
//  DriveInGyeongbuk
//
//  홈(지도) 화면의 상태.
//
//  현재 위치, 목적지 선택, 경로 미리보기 상태를 관리한다.
//

import Combine
import Foundation

final class MapHomeViewModel: ObservableObject {

    /// 위치를 아직 못 잡았을 때 보여 줄 기본 화면. 경상북도청 부근.
    static let fallbackCoordinate = NaverCoordinate(latitude: 36.5760, longitude: 128.5056)
    /// 도 전체가 들어오는 정도의 축척. 현재 위치를 잡으면 `focusZoom` 으로 당긴다.
    private static let fallbackZoom: Double = 9
    private static let focusZoom: Double = 15

    // MARK: 입력

    /// 목적지 검색어.
    @Published var searchText = ""

    // MARK: 출력

    @Published private(set) var authorization: LocationAuthorization = .notDetermined
    /// 위치 권한이 없거나 위치를 못 잡았을 때 화면에 띄울 사유. 정상이면 `nil`.
    @Published private(set) var statusMessage: String?
    @Published private(set) var destination: NaverLocation?
    @Published private(set) var route: DrivingRoute?
    @Published private(set) var safeRoute: DrivingRoute?
    @Published private(set) var isRouteLoading = false
    @Published private(set) var routeErrorMessage: String?
    @Published private(set) var isDriving = false

    /// 지도 조작용.
    let map = NaverMapController()
    /// 경로 미리보기 화면은 홈 지도와 수명 주기가 달라 별도 컨트롤러를 사용한다.
    let routeMap = NaverMapController()

    /// 권한이 있을 때만 현위치 추적을 켠다. 권한 없이 켜면 SDK 가 빈 점을 들고 헛돈다.
    var isTrackingLocation: Bool {
        authorization == .authorized && (destination == nil || isDriving)
    }

    // MARK: 의존성

    private let locationService: LocationServicing
    private let directionsService: NaverDirectionsServicing
    private var routeRequestID: UUID?
    /// 첫 좌표에서 한 번만 카메라를 옮긴다. 이후에는 SDK 의 추적 모드가 맡는다.
    private var hasCenteredOnUser = false

    init(locationService: LocationServicing = LocationService(),
         directionsService: NaverDirectionsServicing = NaverDirectionsService()) {
        self.locationService = locationService
        self.directionsService = directionsService
        self.locationService.onChange = { [weak self] in
            self?.handleLocationChange()
        }
        authorization = locationService.authorization
    }

    // MARK: 화면 이벤트

    func onAppear() {
        // 아직 한 번도 현재 위치로 못 옮겼을 때만 초기 화면을 잡아 준다.
        // 탭을 오갈 때마다 부르면 사용자가 옮겨 둔 카메라를 뺏게 된다.
        if !hasCenteredOnUser {
            if let coordinate = locationService.lastCoordinate {
                centerOnUser(coordinate)
            } else {
                map.focus(on: Self.fallbackCoordinate, zoom: Self.fallbackZoom, animated: false)
            }
        }

        switch locationService.authorization {
        case .notDetermined:
            locationService.requestAuthorization()
        case .authorized:
            locationService.startUpdating()
        case .denied:
            break
        }
        handleLocationChange()
    }

    func onDisappear() {
        locationService.stopUpdating()
    }

    /// 현위치 버튼(또는 권한 허용 직후) — 카메라를 사용자 위치로 되돌린다.
    func recenterOnUser() {
        guard let coordinate = locationService.lastCoordinate else {
            map.moveToCurrentLocation()
            return
        }
        map.focus(on: coordinate, zoom: Self.focusZoom)
        map.moveToCurrentLocation()
    }

    /// 검색 화면에서 고른 목적지를 저장한다. 경로 요청은 미리보기 화면 진입 후 시작한다.
    func prepareDestination(_ location: NaverLocation) {
        routeRequestID = nil
        searchText = location.displayTitle
        destination = location
        route = nil
        safeRoute = nil
        routeErrorMessage = nil
        isRouteLoading = false
        isDriving = false
    }

    func retryRoute() async {
        await loadRoute()
    }

    /// 경로 화면에서 검색 화면으로 돌아갈 때 검색어·목적지는 유지하고 화면 작업만 멈춘다.
    func leaveRoutePreview() {
        routeRequestID = nil
        isRouteLoading = false
        isDriving = false
        routeMap.clear()
    }

    func clearDestination() {
        routeRequestID = nil
        destination = nil
        route = nil
        safeRoute = nil
        routeErrorMessage = nil
        isRouteLoading = false
        isDriving = false
        searchText = ""
        routeMap.clear()
        recenterOnUser()
    }

    func startDriving() {
        isDriving = true
        routeMap.moveToCurrentLocation()
    }

    // MARK: -

    private func handleLocationChange() {
        authorization = locationService.authorization
        statusMessage = Self.message(for: locationService.authorization)

        guard locationService.authorization == .authorized else { return }
        locationService.startUpdating()

        guard !hasCenteredOnUser, let coordinate = locationService.lastCoordinate else { return }
        centerOnUser(coordinate)
    }

    private func loadRoute() async {
        guard let destination else { return }
        guard let start = locationService.lastCoordinate else {
            routeErrorMessage = "현재 위치를 확인한 뒤 다시 시도해 주세요."
            routeMap.focus(on: destination.coordinate, zoom: Self.focusZoom)
            return
        }

        let requestID = UUID()
        routeRequestID = requestID
        isRouteLoading = true
        routeErrorMessage = nil
        defer {
            if routeRequestID == requestID { isRouteLoading = false }
        }

        do {
            let routes = try await directionsService.routes(from: start,
                                                             to: destination.coordinate,
                                                             waypoints: [],
                                                             options: [.fastest, .comfortable])
            guard routeRequestID == requestID, self.destination?.id == destination.id else { return }
            route = routes.first { $0.option == .fastest } ?? routes.first
            safeRoute = routes.first { $0.option == .comfortable }
            if let route { routeMap.showRoute(route) }
        } catch {
            guard routeRequestID == requestID, self.destination?.id == destination.id else { return }
            route = nil
            safeRoute = nil
            routeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 첫 위치로 카메라를 옮긴다.
    ///
    /// 애니메이션 없이 한 번에 옮기는 게 중요하다. 이 시점에는 SDK 의 추적 모드도
    /// 같은 카메라를 계속 만지고 있어서, 애니메이션을 걸면 중간에 잘려 줌이 안 먹는다.
    private func centerOnUser(_ coordinate: NaverCoordinate) {
        hasCenteredOnUser = true
        map.focus(on: coordinate, zoom: Self.focusZoom, animated: false)
    }

    private static func message(for authorization: LocationAuthorization) -> String? {
        switch authorization {
        case .authorized:
            return nil
        case .notDetermined:
            return "Allow location access to see where you are."
        case .denied:
            return "Location is off. Turn it on in Settings to see where you are."
        }
    }
}

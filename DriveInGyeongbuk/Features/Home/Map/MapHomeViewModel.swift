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
    @Published private(set) var selectedRouteOption: RouteOption = .fastest
    @Published private(set) var isRouteLoading = false
    @Published private(set) var routeErrorMessage: String?
    @Published private(set) var isDriving = false
    /// 방금 끝낸 주행. 값이 들어오면 화면이 Debrief 를 띄운다.
    /// 주행을 기록하지 못했으면(위치 권한 없음 등) `nil` 로 남고 지금까지와 똑같이 동작한다.
    @Published private(set) var finishedDrive: DriveRecording?

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
    /// 주행 종료 후 Debrief 를 만들 재료를 모은다. 위치 갱신은 아래 `handleLocationChange` 가 넘겨 준다.
    private let driveRecorder: DriveRecorderProtocol
    private var routeRequestID: UUID?
    /// 첫 좌표에서 한 번만 카메라를 옮긴다. 이후에는 SDK 의 추적 모드가 맡는다.
    private var hasCenteredOnUser = false

    init(locationService: LocationServicing = LocationService(),
         directionsService: NaverDirectionsServicing = NaverDirectionsService(),
         driveRecorder: DriveRecorderProtocol = DriveRecorder()) {
        self.locationService = locationService
        self.directionsService = directionsService
        self.driveRecorder = driveRecorder
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
        selectedRouteOption = .fastest
    }

    func retryRoute() async {
        await loadRoute()
    }

    /// 경로 화면에서 검색 화면으로 돌아갈 때 검색어·목적지는 유지하고 화면 작업만 멈춘다.
    func leaveRoutePreview() {
        routeRequestID = nil
        isRouteLoading = false
        isDriving = false
        // 끝까지 가지 않은 기록은 버린다. 남겨 두면 다음 주행에 섞인다.
        driveRecorder.cancel()
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
        driveRecorder.cancel()
        searchText = ""
        routeMap.clear()
        recenterOnUser()
    }

    func selectRoute(_ option: RouteOption) {
        guard let selected = route(for: option) else { return }
        selectedRouteOption = selected.option
        routeMap.showRoute(selected)
    }

    func startDriving() {
        guard let selectedRoute else { return }
        isDriving = true
        finishedDrive = nil
        driveRecorder.start(route: selectedRoute,
                            originName: nil,
                            destinationName: destination?.displayTitle)
        routeMap.showRoute(selectedRoute, fitsRoute: false, showsEndpoints: false)
        if let currentLocation = locationService.lastCoordinate {
            routeMap.startNavigation(at: currentLocation)
        } else {
            routeMap.moveToCurrentLocation()
        }
    }

    func finishDriving() {
        isDriving = false
        if let selectedRoute { routeMap.showRoute(selectedRoute) }

        // Debrief 는 여기서만 시작된다. 기록이 부실하면(권한 거부·너무 짧은 주행) 띄우지 않는다.
        // 어느 쪽이든 위의 주행 종료 처리는 이미 끝나 있어서 기존 동작이 달라지지 않는다.
        let recording = driveRecorder.finish()
        finishedDrive = recording?.isSubstantial == true ? recording : nil
    }

    /// Debrief 를 닫는다.
    func dismissDebrief() {
        finishedDrive = nil
    }

    var selectedRoute: DrivingRoute? {
        route(for: selectedRouteOption) ?? route
    }

    private func route(for option: RouteOption) -> DrivingRoute? {
        switch option {
        case .comfortable:
            return safeRoute
        default:
            return route
        }
    }

    // MARK: -

    private func handleLocationChange() {
        authorization = locationService.authorization
        statusMessage = Self.message(for: locationService.authorization)

        guard locationService.authorization == .authorized else { return }
        locationService.startUpdating()

        // 주행 중이면 이 갱신을 기록에 남긴다.
        // `LocationServicing.onChange` 는 구독자를 하나만 받아서, 이미 받고 있는 이쪽이
        // 레코더에 넘겨 주는 구조다 (`DriveRecorder` 주석 참고).
        driveRecorder.record(locationService.lastFix)

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

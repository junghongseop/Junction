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
    /// 이 거리 안에 들어오면 도착 임박 UI와 주정차 금지구역을 노출한다.
    private static let destinationApproachDistanceMeters: Double = 300

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
    @Published private(set) var simulationState: RouteSimulationState?
    @Published private(set) var isApproachingDestination = false
    @Published private(set) var parkingRestrictions: [EnforcementZone] = []
    @Published private(set) var isParkingRestrictionsLoading = false
    @Published private(set) var parkingRestrictionErrorMessage: String?
    @Published private(set) var isParkingRouteLoading = false
    @Published private(set) var parkingRouteErrorMessage: String?
    @Published private(set) var selectedParkingLot: ParkingLot?

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
    private let routeSimulator: RouteLocationSimulating
    private let speedLimitService: (any SpeedLimitServicing)?
    private let parkingService: ParkingServicing
    private let enforcementService: EnforcementServicing
    private var routeRequestID: UUID?
    private var simulationStartID: UUID?
    private var parkingRestrictionRequestID: UUID?
    private var parkingRouteRequestID: UUID?
    private var restrictionDestinationID: String?
    /// 첫 좌표에서 한 번만 카메라를 옮긴다. 이후에는 SDK 의 추적 모드가 맡는다.
    private var hasCenteredOnUser = false

    init(locationService: LocationServicing = LocationService(),
         directionsService: NaverDirectionsServicing = NaverDirectionsService(),
         routeSimulator: RouteLocationSimulating = RouteLocationSimulator(),
         speedLimitService: (any SpeedLimitServicing)? = try? SpeedLimitService(),
         parkingService: ParkingServicing = ParkingService(),
         enforcementService: EnforcementServicing = EnforcementService()) {
        self.locationService = locationService
        self.directionsService = directionsService
        self.routeSimulator = routeSimulator
        self.speedLimitService = speedLimitService
        self.parkingService = parkingService
        self.enforcementService = enforcementService
        self.locationService.onChange = { [weak self] in
            self?.handleLocationChange()
        }
        self.routeSimulator.onChange = { [weak self] state in
            self?.handleSimulationChange(state)
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
        simulationStartID = nil
        parkingRestrictionRequestID = nil
        parkingRouteRequestID = nil
        locationService.stopUpdating()
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
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
        simulationStartID = nil
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
        routeRequestID = nil
        parkingRestrictionRequestID = nil
        parkingRouteRequestID = nil
        restrictionDestinationID = nil
        searchText = location.displayTitle
        destination = location
        route = nil
        safeRoute = nil
        routeErrorMessage = nil
        isRouteLoading = false
        isDriving = false
        simulationState = nil
        isApproachingDestination = false
        parkingRestrictions = []
        isParkingRestrictionsLoading = false
        parkingRestrictionErrorMessage = nil
        isParkingRouteLoading = false
        parkingRouteErrorMessage = nil
        selectedParkingLot = nil
        selectedRouteOption = .fastest
        routeMap.clearParkingRestrictions()
    }

    func retryRoute() async {
        await loadRoute()
    }

    /// 경로 화면에서 검색 화면으로 돌아갈 때 검색어·목적지는 유지하고 화면 작업만 멈춘다.
    func leaveRoutePreview() {
        simulationStartID = nil
        routeRequestID = nil
        parkingRestrictionRequestID = nil
        parkingRouteRequestID = nil
        restrictionDestinationID = nil
        isRouteLoading = false
        isDriving = false
        simulationState = nil
        isApproachingDestination = false
        parkingRestrictions = []
        isParkingRestrictionsLoading = false
        isParkingRouteLoading = false
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
        routeMap.clear()
    }

    func clearDestination() {
        simulationStartID = nil
        routeRequestID = nil
        parkingRestrictionRequestID = nil
        parkingRouteRequestID = nil
        restrictionDestinationID = nil
        destination = nil
        route = nil
        safeRoute = nil
        routeErrorMessage = nil
        isRouteLoading = false
        isDriving = false
        simulationState = nil
        isApproachingDestination = false
        parkingRestrictions = []
        isParkingRestrictionsLoading = false
        parkingRestrictionErrorMessage = nil
        isParkingRouteLoading = false
        parkingRouteErrorMessage = nil
        selectedParkingLot = nil
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
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
        beginDriving(on: selectedRoute, departureDelay: 3)
    }

    /// P 버튼 — 현재 주행 좌표에서 가장 가까운 목적지 주변 주차장으로 안내를 바꾼다.
    func navigateToNearestParking() async {
        guard isDriving, !isParkingRouteLoading,
              let destination,
              let currentRoute = selectedRoute else { return }

        let requestID = UUID()
        parkingRouteRequestID = requestID
        isParkingRouteLoading = true
        parkingRouteErrorMessage = nil

        let start = simulationState?.coordinate ?? currentRoute.goal

        do {
            let suggestions = try await parkingService.suggestions(
                near: destination.coordinate,
                radiusMeters: JunctionServerConfiguration.fixedSearchRadiusMeters
            )
            guard parkingRouteRequestID == requestID, isDriving else { return }

            guard let nearest = suggestions.min(by: {
                $0.lot.coordinate.distance(to: start) < $1.lot.coordinate.distance(to: start)
            }) else {
                throw JunctionServerError.httpStatus(code: 404, body: "주변 주차장을 찾지 못했습니다.")
            }

            let routes = try await directionsService.routes(
                from: start,
                to: nearest.lot.coordinate,
                waypoints: [],
                options: [.fastest, .comfortable]
            )
            guard parkingRouteRequestID == requestID, isDriving else { return }

            guard let fastest = routes.first(where: { $0.option == .fastest }) ?? routes.first else {
                throw NaverMapsError.emptyResult
            }

            route = fastest
            safeRoute = routes.first { $0.option == .comfortable }
            selectedRouteOption = fastest.option
            selectedParkingLot = nearest.lot
            isApproachingDestination = fastest.distance <= Int(Self.destinationApproachDistanceMeters)
            beginDriving(on: fastest, departureDelay: 0)
        } catch {
            guard parkingRouteRequestID == requestID else { return }
            parkingRouteErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        if parkingRouteRequestID == requestID {
            isParkingRouteLoading = false
        }
    }

    private func beginDriving(on route: DrivingRoute, departureDelay: TimeInterval) {
        let startID = UUID()
        simulationStartID = startID
        isDriving = true
        simulationState = nil
        routeMap.showRoute(route, fitsRoute: false, showsEndpoints: false)
        let startCoordinate = route.path.first ?? route.start
        routeMap.updateSimulatedVehicle(
            at: startCoordinate,
            bearing: Self.bearingOfFirstSegment(in: route),
            remainingPath: route.path
        )
        updateDestinationApproach(remainingDistance: Double(route.distance))
        let departureDeadline = Date().addingTimeInterval(departureDelay)
        Task {
            var speedSegments: [RouteSpeedLimitSegment] = []
            if let speedLimitService {
                try? await speedLimitService.prepare(for: route)
                speedSegments = speedLimitService.routeSegments
            }
            guard isDriving, simulationStartID == startID else { return }
            let remainingDelay = departureDeadline.timeIntervalSinceNow
            if remainingDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remainingDelay * 1_000_000_000))
            }
            guard isDriving, simulationStartID == startID else { return }
            routeSimulator.start(route: route,
                                 maximumSpeedKilometersPerHour: 100,
                                 speedLimitSegments: speedSegments)
        }
    }

    func finishDriving() {
        simulationStartID = nil
        parkingRouteRequestID = nil
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
        simulationState = nil
        isApproachingDestination = false
        isParkingRouteLoading = false
        isDriving = false
        if let selectedRoute { routeMap.showRoute(selectedRoute) }
    }

    func dismissParkingRouteError() {
        parkingRouteErrorMessage = nil
    }

    var selectedRoute: DrivingRoute? {
        route(for: selectedRouteOption) ?? route
    }

    var currentInstruction: RouteStep? { simulationState?.nextStep }
    var distanceToNextInstruction: Double { simulationState?.distanceToNextStep ?? 0 }
    var remainingDistance: Double { simulationState?.remainingDistance ?? Double(selectedRoute?.distance ?? 0) }
    var simulatedArrivalDate: Date {
        Date().addingTimeInterval(simulationState?.remainingDuration ?? 0)
    }
    var simulatedSpeedKPH: Int { simulationState?.currentSpeedKPH ?? 0 }
    var simulatedSpeedLimitKPH: Int? { simulationState?.speedLimitKPH }
    var hasArrived: Bool { simulationState?.isFinished == true }
    var canFinishDriving: Bool {
        isDriving && isApproachingDestination
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

        guard !hasCenteredOnUser, let coordinate = locationService.lastCoordinate else { return }
        centerOnUser(coordinate)
    }

    private func handleSimulationChange(_ state: RouteSimulationState) {
        simulationState = state
        updateDestinationApproach(remainingDistance: state.remainingDistance)
        if let selectedRoute {
            let nextIndex = min(state.pathIndex + 1, selectedRoute.path.count)
            let remainingPath = [state.coordinate] + Array(selectedRoute.path.dropFirst(nextIndex))
            routeMap.updateSimulatedVehicle(at: state.coordinate,
                                            bearing: state.bearing,
                                            remainingPath: remainingPath)
        }
    }

    private func updateDestinationApproach(remainingDistance: Double) {
        isApproachingDestination = isDriving
            && remainingDistance <= Self.destinationApproachDistanceMeters

        guard isApproachingDestination else { return }
        loadParkingRestrictionsIfNeeded()
    }

    /// 도착 임박 구간에 처음 들어온 순간에만 백엔드를 호출한다.
    private func loadParkingRestrictionsIfNeeded() {
        guard let destination,
              restrictionDestinationID != destination.id,
              !isParkingRestrictionsLoading else { return }

        let requestID = UUID()
        parkingRestrictionRequestID = requestID
        restrictionDestinationID = destination.id
        isParkingRestrictionsLoading = true
        parkingRestrictionErrorMessage = nil

        Task {
            do {
                let zones = try await enforcementService.zones(
                    near: destination.coordinate,
                    radiusMeters: JunctionServerConfiguration.fixedSearchRadiusMeters
                )
                guard parkingRestrictionRequestID == requestID,
                      self.destination?.id == destination.id else { return }
                parkingRestrictions = zones
                routeMap.showParkingRestrictions(zones)
            } catch {
                guard parkingRestrictionRequestID == requestID else { return }
                parkingRestrictionErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }

            if parkingRestrictionRequestID == requestID {
                isParkingRestrictionsLoading = false
            }
        }
    }

    private static func bearingOfFirstSegment(in route: DrivingRoute) -> Double {
        guard route.path.count >= 2 else { return 0 }
        let start = route.path[0]
        let end = route.path[1]
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
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
            if let route, route.usesTollRoad {
                selectedRouteOption = route.option
                routeMap.showRoute(route)
            } else if let safeRoute {
                selectedRouteOption = safeRoute.option
                routeMap.showRoute(safeRoute)
            } else if let route {
                selectedRouteOption = route.option
                routeMap.showRoute(route)
            }
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

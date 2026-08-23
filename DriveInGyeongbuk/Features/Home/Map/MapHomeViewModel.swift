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
    @Published private(set) var isPreviewingParkingRoute = false
    @Published private(set) var parkingRouteErrorMessage: String?
    @Published private(set) var selectedParkingLot: ParkingLot?
    /// 방금 끝낸 주행. 값이 들어오면 화면이 Debrief 를 띄운다.
    /// 주행을 기록하지 못했으면(너무 짧은 주행 등) `nil` 로 남고 지금까지와 똑같이 동작한다.
    @Published private(set) var finishedDrive: DriveRecording?

    /// 지도 조작용.
    let map = NaverMapController()
    /// 경로 미리보기 화면은 홈 지도와 수명 주기가 달라 별도 컨트롤러를 사용한다.
    let routeMap = NaverMapController()

    /// 권한이 있을 때만 현위치 추적을 켠다. 권한 없이 켜면 SDK 가 빈 점을 들고 헛돈다.
    var isTrackingLocation: Bool {
        !locationService.isSimulated
            && authorization == .authorized
            && (destination == nil || isDriving)
    }

    // MARK: 의존성

    private let locationService: LocationServicing
    private let directionsService: NaverDirectionsServicing
    private let routeSimulator: RouteLocationSimulating
    private let speedLimitService: (any SpeedLimitServicing)?
    private let parkingService: ParkingServicing
    private let enforcementService: EnforcementServicing
    /// 주행 종료 후 Debrief 를 만들 재료를 모은다.
    /// 주행 좌표는 시뮬레이터가 만들므로 아래 `handleSimulationChange` 가 넘겨 준다.
    private let driveRecorder: DriveRecorderProtocol

    /// 주행 기록을 Debrief 로 바꾸는 서비스.
    ///
    /// 화면이 `DebriefService()` 를 직접 만들지 않고 여기서 넘겨 주는 이유:
    /// 주행 중에 이미 열어 둔 제한속도 DB(34MB SQLite)와, 도착 임박에 이미 받아 둔
    /// 주정차 금지구간을 **그대로 재사용**하기 위해서다. 새로 만들면 주행이 끝난 화면에서
    /// 같은 것을 처음부터 다시 하느라 로딩만 길어진다(무료 호스팅은 콜드 스타트가 수십 초다).
    private(set) lazy var debriefService: DebriefServicing = DebriefService(
        enforcementService: enforcementService,
        speedLimitServiceFactory: { [weak self] in self?.speedLimitService }
    )

    private var routeRequestID: UUID?
    private var simulationStartID: UUID?
    private var parkingRestrictionRequestID: UUID?
    private var parkingRouteRequestID: UUID?
    private var restrictionDestinationID: String?
    /// 첫 좌표에서 한 번만 카메라를 옮긴다. 이후에는 SDK 의 추적 모드가 맡는다.
    private var hasCenteredOnUser = false

    init(locationService: LocationServicing = makeDefaultLocationService(),
         directionsService: NaverDirectionsServicing = NaverDirectionsService(),
         routeSimulator: RouteLocationSimulating = RouteLocationSimulator(),
         speedLimitService: (any SpeedLimitServicing)? = try? SpeedLimitService(),
         parkingService: ParkingServicing = ParkingService(),
         enforcementService: EnforcementServicing = EnforcementService(),
         driveRecorder: DriveRecorderProtocol = DriveRecorder()) {
        self.locationService = locationService
        self.directionsService = directionsService
        self.routeSimulator = routeSimulator
        self.speedLimitService = speedLimitService
        self.parkingService = parkingService
        self.enforcementService = enforcementService
        self.driveRecorder = driveRecorder
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
        // 주행 중이면 아무것도 멈추지 않는다.
        //
        // Map 탭을 벗어나기만 해도 여기까지 온다. 예전에는 그때 시뮬레이터를 멈춰 버려서,
        // Trip 탭을 한 번 눌렀다 돌아오면 안내 화면은 그대로인데 차만 멈춰 있었다.
        // 되살릴 방법도 없었다 — `onAppear` 는 주행을 다시 시작하지 않는다.
        // 주행은 화면을 잠깐 벗어난다고 끝나는 일이 아니다.
        guard !isDriving else { return }

        simulationStartID = nil
        parkingRestrictionRequestID = nil
        parkingRouteRequestID = nil
        isPreviewingParkingRoute = false
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
        if locationService.isSimulated {
            map.showSimulatedCurrentLocation(at: coordinate)
        } else {
            map.moveToCurrentLocation()
        }
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
        isPreviewingParkingRoute = false
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
        isPreviewingParkingRoute = false
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
        // 끝까지 가지 않은 기록은 버린다. 남겨 두면 다음 주행에 섞인다.
        driveRecorder.cancel()
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
        isPreviewingParkingRoute = false
        parkingRouteErrorMessage = nil
        selectedParkingLot = nil
        routeSimulator.stop()
        routeMap.removeSimulatedVehicle()
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
        beginDriving(on: selectedRoute, departureDelay: 3)
    }

    /// P 버튼 — 현재 주행 좌표에서 가장 가까운 목적지 주변 주차장으로 안내를 바꾼다.
    func navigateToNearestParking() async {
        guard isDriving, !isParkingRouteLoading,
              let destination,
              selectedRoute != nil else { return }

        // P를 누른 바로 그 지점을 새 경로의 출발점으로 고정한다. 좌표가 아직 발행되기 전인데
        // 기존 목적지(`route.goal`)로 대신하면 주차 경로가 목적지에서 시작해 버린다.
        guard let start = simulationState?.coordinate else {
            parkingRouteErrorMessage = "현재 주행 위치를 확인한 뒤 다시 시도해 주세요."
            return
        }

        let requestID = UUID()
        parkingRouteRequestID = requestID
        isParkingRouteLoading = true
        parkingRouteErrorMessage = nil

        // 네트워크 응답을 기다리는 동안 차가 계속 이동하면 탐색 출발점과 화면의 차량 위치가
        // 달라지고, 기존 카메라 갱신이 새 전체 경로 카메라를 덮는다. 진행 상태를 보존해 멈춰
        // 두었다가 실패한 경우에만 같은 지점에서 재개한다.
        simulationStartID = nil
        routeSimulator.pause()

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

            // 이후에는 기존 시뮬레이터 상태가 필요 없다. 새 경로를 넣기 전에 완전히 비워서
            // 전체 경로 보기와 줌인 사이에 예전 카메라 갱신이 끼어들지 못하게 한다.
            routeSimulator.stop()
            route = fastest
            safeRoute = routes.first { $0.option == .comfortable }
            selectedRouteOption = fastest.option
            selectedParkingLot = nearest.lot
            isApproachingDestination = fastest.distance <= Int(Self.destinationApproachDistanceMeters)

            // 새 경로를 전체 보기로 먼저 보여 준다.
            isPreviewingParkingRoute = true
            routeMap.showParkingRouteOverview(fastest)

            // 전체 경로 카메라 이동(0.9초) 뒤 약 1.2초간 경로를 읽을 시간을 준다.
            try? await Task.sleep(nanoseconds: 2_100_000_000)
            guard parkingRouteRequestID == requestID, isDriving else { return }

            let routeStart = fastest.path.first ?? fastest.start
            routeMap.focusOnNavigationVehicle(
                at: routeStart,
                bearing: Self.bearingOfFirstSegment(in: fastest)
            )

            // 차량 줌인 애니메이션이 끝난 다음 시뮬레이션을 재개해야 카메라가 튀지 않는다.
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            guard parkingRouteRequestID == requestID, isDriving else { return }
            isPreviewingParkingRoute = false
            beginDriving(on: fastest, departureDelay: 0, preparesMap: false, startsRecording: false)
        } catch {
            guard parkingRouteRequestID == requestID else { return }
            parkingRouteErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if isDriving {
                routeSimulator.resume()
            }
        }

        if parkingRouteRequestID == requestID {
            isParkingRouteLoading = false
        }
    }

    private func beginDriving(on route: DrivingRoute,
                              departureDelay: TimeInterval,
                              preparesMap: Bool = true,
                              startsRecording: Bool = true) {
        let startID = UUID()
        simulationStartID = startID
        isDriving = true
        // 주차장으로 안내를 바꾸는 경우(`startsRecording == false`)는 같은 주행의 연장이다.
        // 여기서 다시 `start` 하면 지금까지 모은 샘플을 통째로 버리게 된다.
        if startsRecording {
            finishedDrive = nil
            driveRecorder.start(route: route,
                                originName: locationService.isSimulated ? DemoDriveLocation.originName : nil,
                                destinationName: destination?.displayTitle)
        }
        simulationState = nil
        let startCoordinate = route.path.first ?? route.start
        if preparesMap {
            routeMap.showRoute(route, fitsRoute: false, showsEndpoints: false)
            routeMap.updateSimulatedVehicle(
                at: startCoordinate,
                bearing: Self.bearingOfFirstSegment(in: route),
                remainingPath: route.path
            )
        }
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
        isPreviewingParkingRoute = false
        isDriving = false
        if let selectedRoute { routeMap.showRoute(selectedRoute) }

        // Debrief 는 여기서만 시작된다.
        //
        // 기록이 짧다는 이유로 걸러 내지 않는다. 사용자가 Finish 를 눌렀다는 건
        // "여기까지의 주행에 대해 말해 달라"는 뜻이고, 아무 화면도 안 띄우면
        // 버튼이 고장 난 것처럼 보인다(실제로 그렇게 보였다). 감지할 게 없는 주행이면
        // Debrief 가 "이번엔 특별한 게 없었다"고 말해 준다 — 그쪽이 정직하다.
        //
        // 짧은 주행이라는 사실 자체는 `DriveRecording.isSubstantial` 로 화면이 판단해
        // 빈 상태 문구를 바꾼다.
        finishedDrive = driveRecorder.finish()
    }

    /// Debrief 를 닫는다.
    func dismissDebrief() {
        finishedDrive = nil
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
    var isAboveDebriefSpeedThreshold: Bool {
        guard let limit = simulatedSpeedLimitKPH else { return false }
        return simulatedSpeedKPH > limit + 5
    }
    var hasArrived: Bool { simulationState?.isFinished == true }

    /// 주행 종료 버튼을 보여 줄지.
    ///
    /// 주행 중에는 **항상** 보여 준다. 도착 임박일 때만 띄웠더니, 주행 화면은
    /// 네비게이션 바를 숨기기 때문에 중간에 그만두려면 나갈 길이 없었다.
    var canFinishDriving: Bool { isDriving }

    /// 주차장 안내(P) 버튼을 보여 줄지. 이쪽은 도착 임박일 때만 의미가 있다.
    var canSuggestParking: Bool {
        isDriving && isApproachingDestination && selectedParkingLot == nil
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
        // 주행 좌표는 실제 GPS 가 아니라 시뮬레이터가 만든다(`RouteLocationSimulator`).
        // Debrief 도 화면과 같은 좌표를 봐야 하므로 여기서 레코더에 넘긴다.
        // 실제 GPS 로 갈아탈 때는 이 한 줄 대신 `handleLocationChange` 에서 `lastFix` 를 넘기면 된다.
        driveRecorder.record(DriveSample(coordinate: state.coordinate,
                                        timestamp: .now,
                                        speedKPH: state.currentSpeedKPH,
                                        courseDegrees: state.bearing))
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
        if locationService.isSimulated {
            map.showSimulatedCurrentLocation(at: coordinate)
        }
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

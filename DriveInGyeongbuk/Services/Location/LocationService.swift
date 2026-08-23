//
//  LocationService.swift
//  DriveInGyeongbuk
//
//  기기의 현재 위치를 다루는 최소 래퍼.
//
//  지도의 "현위치 파란 점"은 네이버 SDK 의 `positionMode` 가 알아서 그린다.
//  이 서비스가 맡는 건 두 가지다.
//    ① 위치 권한을 요청하고 그 결과를 화면에 알려 준다
//       (권한이 없으면 SDK 는 아무 말 없이 점을 안 그린다)
//    ② 첫 카메라 이동에 쓸 좌표를 준다
//
//  주행 중 경로 추적용 고빈도 갱신은 아직 필요 없어서 정확도를 `kCLLocationAccuracyBest`
//  로만 잡아 두었다. 내비 화면을 붙일 때 갱신 주기/백그라운드 설정을 다시 봐야 한다.
//

import CoreLocation
import Foundation

/// 위치 권한 상태를 화면이 쓰기 편한 형태로 줄인 것.
nonisolated enum LocationAuthorization {
    /// 아직 물어본 적이 없다.
    case notDetermined
    /// 사용자가 거부했거나 기기 정책으로 막혀 있다.
    case denied
    /// 사용 가능.
    case authorized
}

/// 위치 갱신 한 건. 좌표 말고 속도·시각까지 필요한 쪽(주행 기록)이 쓴다.
///
/// `lastCoordinate` 만으로는 "얼마나 빨리 달렸는지"를 알 수 없어서 나중에 덧붙였다.
/// 기존 호출부는 계속 `lastCoordinate` 를 쓰면 된다 — 그 의미는 바뀌지 않았다.
nonisolated struct LocationFix: Hashable {
    var coordinate: NaverCoordinate
    var timestamp: Date
    /// 대지 속도(m/s). CoreLocation 이 속도를 못 잰 경우(음수)는 `nil` 로 걸러 둔다.
    var speedMPS: Double?
    /// 진행 방위(도). 못 잰 경우(음수)는 `nil`.
    var courseDegrees: Double?

    init(_ location: CLLocation) {
        coordinate = NaverCoordinate(location.coordinate)
        timestamp = location.timestamp
        speedMPS = location.speed >= 0 ? location.speed : nil
        courseDegrees = location.course >= 0 ? location.course : nil
    }
}

/// 테스트/목 교체를 위한 추상화.
protocol LocationServicing: AnyObject {
    var authorization: LocationAuthorization { get }
    /// 실제 기기 GPS 대신 데모 좌표를 쓰는 구현인지.
    var isSimulated: Bool { get }
    /// 마지막으로 받은 좌표. 아직 한 번도 못 받았으면 `nil`.
    var lastCoordinate: NaverCoordinate? { get }
    /// 마지막 위치 갱신 원본(속도·방위·시각 포함). 주행 기록용.
    var lastFix: LocationFix? { get }
    /// 권한 또는 좌표가 바뀔 때마다 불린다.
    var onChange: (() -> Void)? { get set }

    func requestAuthorization()
    func startUpdating()
    func stopUpdating()
}

extension LocationServicing {
    var isSimulated: Bool { false }
}

/// 데모 영상에서 쓸 고정 출발지와 목적지.
///
/// 영천공설시장에서 영천시청까지는 직선거리 약 1km다. 영천시청 주변에서는
/// 운영 백엔드가 시청남길·삼산길·충효로·야사1길 금지구간을 반환한다.
enum DemoDriveLocation {
    static let originName = "영천공설시장"
    static let originCoordinate = NaverCoordinate(latitude: 35.9645099,
                                                  longitude: 128.9374072)
    static let destinationName = "영천시청"
    /// 네이버 Geocoding 에 공식 주소(경상북도 영천시 시청로 16)를 조회한 좌표.
    static let destinationCoordinate = NaverCoordinate(latitude: 35.9732599,
                                                       longitude: 128.9386130)

    static var destination: NaverLocation {
        NaverLocation(title: destinationName,
                      category: "공공기관 > 시청",
                      description: "",
                      roadAddress: "경상북도 영천시 시청로 16",
                      jibunAddress: "경상북도 영천시 문외동 27",
                      englishAddress: "16 Sicheong-ro, Yeongcheon-si, Gyeongsangbuk-do",
                      coordinate: destinationCoordinate,
                      link: URL(string: "https://www.yc.go.kr"))
    }

    /// 자동 시연을 끄고 수동으로 점검해야 할 때는 Scheme launch argument 에
    /// `--disable-auto-demo` 를 추가한다. 위치는 계속 고정 좌표를 쓰므로 같은 조건에서
    /// 각 화면을 천천히 확인할 수 있다.
    static var isAutomationEnabled: Bool {
        isEnabled && !ProcessInfo.processInfo.arguments.contains("--disable-auto-demo")
    }

    static var isEnabled: Bool {
#if DEBUG
        true
#else
        false
#endif
    }
}

/// 디버그 데모에서 Core Location 대신 고정 좌표를 공급한다.
/// Release 빌드는 아래 `makeDefaultLocationService()`에서 실제 `LocationService`를 쓴다.
final class DemoLocationService: LocationServicing {
    private(set) var authorization: LocationAuthorization = .authorized
    let isSimulated = true
    private(set) var lastCoordinate: NaverCoordinate?
    private(set) var lastFix: LocationFix?
    var onChange: (() -> Void)?

    init(coordinate: NaverCoordinate = DemoDriveLocation.originCoordinate) {
        lastCoordinate = coordinate
    }

    func requestAuthorization() {
        onChange?()
    }

    func startUpdating() {}

    func stopUpdating() {}
}

func makeDefaultLocationService() -> LocationServicing {
    DemoDriveLocation.isEnabled ? DemoLocationService() : LocationService()
}

final class LocationService: NSObject, LocationServicing, CLLocationManagerDelegate {

    private(set) var authorization: LocationAuthorization = .notDetermined
    private(set) var lastCoordinate: NaverCoordinate?
    private(set) var lastFix: LocationFix?
    var onChange: (() -> Void)?

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.delegate = self
        authorization = Self.reduce(manager.authorizationStatus)
    }

    func requestAuthorization() {
        // 이미 결정된 상태에서 다시 부르면 시스템이 무시한다. 설정 앱으로 보내는 건 화면 몫.
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        guard authorization == .authorized else { return }
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = Self.reduce(manager.authorizationStatus)
        if authorization == .authorized {
            manager.startUpdatingLocation()
        }
        onChange?()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(location)
        lastFix = fix
        lastCoordinate = fix.coordinate
        onChange?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 일시적인 실패(예: 실내에서 GPS 를 못 잡음)는 계속 재시도되므로 화면에 띄우지 않는다.
        // 권한 문제는 didChangeAuthorization 으로 따로 들어온다.
    }

    // MARK: -

    private static func reduce(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }
}

// MARK: - Route simulation

/// 앱 내부 주행 시뮬레이터가 내보내는 한 시점의 가짜 위치 상태.
struct RouteSimulationState {
    var coordinate: NaverCoordinate
    var bearing: Double
    var pathIndex: Int
    var remainingDistance: Double
    var remainingDuration: TimeInterval
    var nextStep: RouteStep?
    var distanceToNextStep: Double
    var currentSpeedKPH: Int
    var speedLimitKPH: Int?
    var isFinished: Bool
}

protocol RouteLocationSimulating: AnyObject {
    var onChange: ((RouteSimulationState) -> Void)? { get set }
    func start(route: DrivingRoute,
               maximumSpeedKilometersPerHour: Double,
               speedLimitSegments: [RouteSpeedLimitSegment])
    /// 현재 진행 위치를 보존한 채 좌표 갱신만 잠시 멈춘다.
    func pause()
    /// `pause()` 직전의 진행 위치부터 좌표 갱신을 다시 시작한다.
    func resume()
    func stop()
}

/// 실제 GPS 대신 선택 경로 위를 자연스러운 가감속과 조향으로 이동하는 좌표 공급자.
final class RouteLocationSimulator: RouteLocationSimulating {
    var onChange: ((RouteSimulationState) -> Void)?

    private enum DemoSpeedingPhase {
        case waiting
        case active
        case completed
    }

    private var timer: Timer?
    private var route: DrivingRoute?
    private var cumulativeDistances: [Double] = []
    private var speedLimitSegments: [RouteSpeedLimitSegment] = []
    private var traveledDistance: Double = 0
    private var maximumSpeedKPH: Double = 0
    private var simulatedSpeedKPH: Double = 0
    private var smoothedBearing: Double?
    private var cruiseFactor: Double = 0.9
    private var accelerationKPHPerSecond: Double = 5
    private var decelerationKPHPerSecond: Double = 7
    private var nextCruiseAdjustment = Date.distantPast
    private var lastTick: Date?
    /// 브리프의 과속 감지 기준을 확실히 넘긴 실제 연속 시간.
    private var demoSpeedingQualifiedSeconds: TimeInterval = 0
    private var demoSpeedingPhase: DemoSpeedingPhase = .waiting

    func start(route: DrivingRoute,
               maximumSpeedKilometersPerHour: Double = 100,
               speedLimitSegments: [RouteSpeedLimitSegment] = []) {
        stop()
        guard route.path.count >= 2 else { return }

        self.route = route
        maximumSpeedKPH = max(0, maximumSpeedKilometersPerHour)
        self.speedLimitSegments = speedLimitSegments
        cumulativeDistances = [0]
        for index in 1..<route.path.count {
            cumulativeDistances.append(cumulativeDistances[index - 1]
                                       + route.path[index - 1].distance(to: route.path[index]))
        }
        traveledDistance = 0
        simulatedSpeedKPH = 0
        smoothedBearing = nil
        demoSpeedingQualifiedSeconds = 0
        demoSpeedingPhase = .waiting
        chooseNextCruiseBehavior(at: Date())
        lastTick = Date()
        publishState()
        scheduleTimer()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
        // 대기 시간을 이동 시간으로 계산하지 않도록 재개 시각부터 다시 잰다.
        lastTick = nil
    }

    func resume() {
        guard timer == nil, route != nil, cumulativeDistances.count >= 2 else { return }
        lastTick = Date()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        route = nil
        cumulativeDistances = []
        speedLimitSegments = []
        traveledDistance = 0
        simulatedSpeedKPH = 0
        smoothedBearing = nil
        demoSpeedingQualifiedSeconds = 0
        demoSpeedingPhase = .waiting
        lastTick = nil
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = Date()
        let delta = min(0.5, now.timeIntervalSince(lastTick ?? now))
        lastTick = now
        if now >= nextCruiseAdjustment { chooseNextCruiseBehavior(at: now) }
        updateDemoSpeedingActivation()

        let desiredSpeed = desiredSpeedKPH(at: traveledDistance)
        var rate = desiredSpeed >= simulatedSpeedKPH
            ? accelerationKPHPerSecond
            : decelerationKPHPerSecond
        if demoSpeedingPhase == .active, desiredSpeed >= simulatedSpeedKPH {
            rate = max(rate, 12)
        }
        let maximumChange = rate * delta
        let difference = desiredSpeed - simulatedSpeedKPH
        simulatedSpeedKPH += min(max(difference, -maximumChange), maximumChange)
        simulatedSpeedKPH = max(0, simulatedSpeedKPH)
        traveledDistance += simulatedSpeedKPH / 3.6 * delta
        if let totalDistance = cumulativeDistances.last,
           totalDistance - traveledDistance < 1.5 {
            traveledDistance = totalDistance
            simulatedSpeedKPH = 0
        }
        updateDemoSpeedingProgress(delta: delta)
        updateBearing(delta: delta)
        publishState()
    }

    private func publishState() {
        guard let route, let totalDistance = cumulativeDistances.last else { return }
        traveledDistance = min(traveledDistance, totalDistance)

        let sample = coordinate(at: traveledDistance)
        let segmentIndex = sample.pathIndex
        let coordinate = sample.coordinate
        let remainingDistance = max(0, totalDistance - traveledDistance)
        let speedLimit = reliableSpeedLimit(at: traveledDistance)
        let nextStep = route.steps.first { $0.pointIndex > segmentIndex }
        let nextStepDistance = nextStep.map {
            max(0, cumulativeDistances[min($0.pointIndex, cumulativeDistances.count - 1)] - traveledDistance)
        } ?? remainingDistance
        let finished = traveledDistance >= totalDistance

        onChange?(RouteSimulationState(
            coordinate: coordinate,
            bearing: smoothedBearing ?? desiredBearing(),
            pathIndex: segmentIndex,
            remainingDistance: remainingDistance,
            remainingDuration: remainingDuration(from: traveledDistance, totalDistance: totalDistance),
            nextStep: nextStep,
            distanceToNextStep: nextStepDistance,
            currentSpeedKPH: Int(simulatedSpeedKPH.rounded()),
            speedLimitKPH: speedLimit,
            isFinished: finished
        ))

        if finished { timer?.invalidate(); timer = nil }
    }

    private func segment(containing distance: Double) -> Int {
        guard cumulativeDistances.count >= 2 else { return 0 }
        var low = 0
        var high = cumulativeDistances.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if cumulativeDistances[middle] <= distance { low = middle } else { high = middle }
        }
        return min(low, cumulativeDistances.count - 2)
    }

    private func reliableSpeedLimit(at distance: Double) -> Int? {
        reliableSpeedLimitSegment(at: distance)?.limitKPH
    }

    private func reliableSpeedLimitSegment(at distance: Double) -> RouteSpeedLimitSegment? {
        speedLimitSegments.last {
            $0.distanceFromStartMeters <= distance
                && distance <= $0.endDistanceFromStartMeters
                && $0.isReliableLimit
        }
    }

    private func desiredSpeedKPH(at distance: Double) -> Double {
        guard let totalDistance = cumulativeDistances.last else { return 0 }
        let roadMaximum = min(maximumSpeedKPH,
                              Double(reliableSpeedLimit(at: distance) ?? Int(maximumSpeedKPH)))
        var desired = roadMaximum * cruiseFactor

        // 자동 데모에서는 제한속도보다 충분히 높은 목표 속도를 잠깐 유지해
        // `SustainedSpeedingDetector`가 설명할 수 있는 실제 주행 사건을 만든다.
        if DemoDriveLocation.isAutomationEnabled,
           demoSpeedingPhase == .active,
           let limit = reliableSpeedLimit(at: distance) {
            desired = max(desired, min(maximumSpeedKPH, Double(limit + 15)))
        }

        // 목적지에 가까워지면 일정한 감속도로 자연스럽게 0까지 내려간다.
        let remaining = max(0, totalDistance - distance)
        let stoppingSpeed = sqrt(2 * 1.8 * remaining) * 3.6
        desired = min(desired, stoppingSpeed)
        return max(0, desired)
    }

    /// 출발·도착 감속 구간을 피해 제한속도 정보가 실제로 잡힌 도로에서만 시작한다.
    private func updateDemoSpeedingActivation() {
        guard DemoDriveLocation.isAutomationEnabled,
              demoSpeedingPhase == .waiting,
              let totalDistance = cumulativeDistances.last,
              traveledDistance >= 60,
              totalDistance - traveledDistance >= 350,
              reliableSpeedLimit(at: traveledDistance) != nil else { return }
        demoSpeedingPhase = .active
    }

    /// 감지 기준은 `> 제한속도 + 5km/h`가 5초 이상이다. 샘플링 경계 오차까지
    /// 감안해 실제 속도로 7초를 채운 뒤 정상 순항으로 돌아간다.
    private func updateDemoSpeedingProgress(delta: TimeInterval) {
        guard demoSpeedingPhase == .active else { return }
        guard let limit = reliableSpeedLimit(at: traveledDistance) else {
            demoSpeedingQualifiedSeconds = 0
            demoSpeedingPhase = .waiting
            return
        }

        if simulatedSpeedKPH > Double(limit + 5) {
            demoSpeedingQualifiedSeconds += delta
            if demoSpeedingQualifiedSeconds >= 7 {
                demoSpeedingPhase = .completed
            }
        } else {
            demoSpeedingQualifiedSeconds = 0
        }
    }

    private func chooseNextCruiseBehavior(at date: Date) {
        // 대체로 제한속도 아래에서 달리되, 가끔은 짧게 2~7% 정도 더 밟는다.
        // 목표값만 바꾸므로 실제 속도는 아래 가속률을 따라 서서히 접근한다.
        if Double.random(in: 0...1) < 0.22 {
            cruiseFactor = Double.random(in: 1.02...1.07)
        } else if Bool.random() {
            cruiseFactor = min(0.99, cruiseFactor + Double.random(in: 0.04...0.12))
        } else {
            cruiseFactor = max(0.78, cruiseFactor - Double.random(in: 0.03...0.10))
        }
        accelerationKPHPerSecond = Double.random(in: 5.5...9.0)
        decelerationKPHPerSecond = Double.random(in: 4.0...8.0)
        nextCruiseAdjustment = date.addingTimeInterval(Double.random(in: 3.5...7.0))
    }

    private func updateBearing(delta: TimeInterval) {
        let target = desiredBearing()
        guard let current = smoothedBearing else {
            smoothedBearing = target
            return
        }
        let shortestDifference = (target - current + 540).truncatingRemainder(dividingBy: 360) - 180
        let smoothing = 1 - exp(-1.35 * delta)
        let desiredChange = shortestDifference * smoothing
        // 급커브에서도 지도가 한 번에 휙 돌지 않도록 회전 속도를 제한한다.
        let maximumChange = 32 * delta
        let appliedChange = min(max(desiredChange, -maximumChange), maximumChange)
        smoothedBearing = (current + appliedChange + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private func desiredBearing() -> Double {
        guard cumulativeDistances.count >= 2 else { return 0 }
        let current = coordinate(at: traveledDistance).coordinate
        // 속도가 빠를수록 더 멀리 내다봐 작은 경로 꺾임에 카메라가 흔들리지 않게 한다.
        let lookAhead = min(110, max(35, simulatedSpeedKPH / 3.6 * 2.2))
        let ahead = coordinate(at: traveledDistance + lookAhead).coordinate
        guard current.distance(to: ahead) > 0.5 else { return smoothedBearing ?? 0 }
        return Self.bearing(from: current, to: ahead)
    }

    private func coordinate(at distance: Double) -> (coordinate: NaverCoordinate, pathIndex: Int) {
        guard let route, route.path.count >= 2 else {
            return (NaverCoordinate(latitude: 0, longitude: 0), 0)
        }
        let clampedDistance = min(max(0, distance), cumulativeDistances.last ?? 0)
        let pathIndex = segment(containing: clampedDistance)
        let endIndex = min(pathIndex + 1, route.path.count - 1)
        let segmentStart = cumulativeDistances[pathIndex]
        let segmentLength = max(0.001, cumulativeDistances[endIndex] - segmentStart)
        let progress = min(1, max(0, (clampedDistance - segmentStart) / segmentLength))
        let start = route.path[pathIndex]
        let end = route.path[endIndex]
        return (NaverCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress
        ), pathIndex)
    }

    private func remainingDuration(from distance: Double, totalDistance: Double) -> TimeInterval {
        guard maximumSpeedKPH > 0 else { return 0 }
        var cursor = distance
        var duration: TimeInterval = 0

        for segment in speedLimitSegments where segment.endDistanceFromStartMeters > cursor {
            let segmentStart = max(cursor, segment.distanceFromStartMeters)
            if segmentStart > cursor {
                duration += (segmentStart - cursor) / (maximumSpeedKPH / 3.6)
            }
            let segmentEnd = min(totalDistance, segment.endDistanceFromStartMeters)
            guard segmentEnd > segmentStart else { continue }
            let limit = segment.isReliableLimit ? Double(segment.limitKPH ?? Int(maximumSpeedKPH)) : maximumSpeedKPH
            duration += (segmentEnd - segmentStart) / (min(maximumSpeedKPH, limit) / 3.6)
            cursor = segmentEnd
            if cursor >= totalDistance { break }
        }
        if cursor < totalDistance {
            duration += (totalDistance - cursor) / (maximumSpeedKPH / 3.6)
        }
        return duration
    }

    private static func bearing(from start: NaverCoordinate, to end: NaverCoordinate) -> Double {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

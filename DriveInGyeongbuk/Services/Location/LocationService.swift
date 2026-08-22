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

/// 테스트/목 교체를 위한 추상화.
protocol LocationServicing: AnyObject {
    var authorization: LocationAuthorization { get }
    /// 마지막으로 받은 좌표. 아직 한 번도 못 받았으면 `nil`.
    var lastCoordinate: NaverCoordinate? { get }
    /// 권한 또는 좌표가 바뀔 때마다 불린다.
    var onChange: (() -> Void)? { get set }

    func requestAuthorization()
    func startUpdating()
    func stopUpdating()
}

final class LocationService: NSObject, LocationServicing, CLLocationManagerDelegate {

    private(set) var authorization: LocationAuthorization = .notDetermined
    private(set) var lastCoordinate: NaverCoordinate?
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
        lastCoordinate = NaverCoordinate(location.coordinate)
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
    func stop()
}

/// 실제 GPS 대신 선택 경로 위를 일정 속도로 이동하는 좌표 공급자.
final class RouteLocationSimulator: RouteLocationSimulating {
    var onChange: ((RouteSimulationState) -> Void)?

    private var timer: Timer?
    private var route: DrivingRoute?
    private var cumulativeDistances: [Double] = []
    private var speedLimitSegments: [RouteSpeedLimitSegment] = []
    private var traveledDistance: Double = 0
    private var maximumSpeedKPH: Double = 0
    private var lastTick: Date?

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
        lastTick = Date()
        publishState()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        route = nil
        cumulativeDistances = []
        speedLimitSegments = []
        traveledDistance = 0
        lastTick = nil
    }

    private func tick() {
        let now = Date()
        let delta = min(0.5, now.timeIntervalSince(lastTick ?? now))
        lastTick = now
        traveledDistance += currentSpeedKPH(at: traveledDistance) / 3.6 * delta
        publishState()
    }

    private func publishState() {
        guard let route, let totalDistance = cumulativeDistances.last else { return }
        traveledDistance = min(traveledDistance, totalDistance)

        let segmentIndex = segment(containing: traveledDistance)
        let start = route.path[segmentIndex]
        let endIndex = min(segmentIndex + 1, route.path.count - 1)
        let end = route.path[endIndex]
        let segmentStart = cumulativeDistances[segmentIndex]
        let segmentLength = max(0.001, cumulativeDistances[endIndex] - segmentStart)
        let progress = min(1, max(0, (traveledDistance - segmentStart) / segmentLength))
        let coordinate = NaverCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress
        )
        let remainingDistance = max(0, totalDistance - traveledDistance)
        let speedLimit = reliableSpeedLimit(at: traveledDistance)
        let currentSpeed = currentSpeedKPH(at: traveledDistance)
        let nextStep = route.steps.first { $0.pointIndex > segmentIndex }
        let nextStepDistance = nextStep.map {
            max(0, cumulativeDistances[min($0.pointIndex, cumulativeDistances.count - 1)] - traveledDistance)
        } ?? remainingDistance
        let finished = traveledDistance >= totalDistance

        onChange?(RouteSimulationState(
            coordinate: coordinate,
            bearing: Self.bearing(from: start, to: end),
            pathIndex: segmentIndex,
            remainingDistance: remainingDistance,
            remainingDuration: remainingDuration(from: traveledDistance, totalDistance: totalDistance),
            nextStep: nextStep,
            distanceToNextStep: nextStepDistance,
            currentSpeedKPH: Int(currentSpeed.rounded()),
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
        speedLimitSegments.last {
            $0.distanceFromStartMeters <= distance
                && distance <= $0.endDistanceFromStartMeters
                && $0.isReliableLimit
        }?.limitKPH
    }

    private func currentSpeedKPH(at distance: Double) -> Double {
        min(maximumSpeedKPH, Double(reliableSpeedLimit(at: distance) ?? Int(maximumSpeedKPH)))
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

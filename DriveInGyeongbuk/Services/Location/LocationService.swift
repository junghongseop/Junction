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

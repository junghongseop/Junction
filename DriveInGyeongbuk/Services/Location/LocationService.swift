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

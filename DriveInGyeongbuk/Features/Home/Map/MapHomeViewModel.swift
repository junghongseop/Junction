//
//  MapHomeViewModel.swift
//  DriveInGyeongbuk
//
//  홈(지도) 화면의 상태.
//
//  지금은 "현재 위치를 중심으로 지도를 띄운다"까지만 한다.
//  검색 필드는 자리를 잡아 두었을 뿐 아직 Geocoding 을 태우지 않는다
//  (목적지 검색 결과 화면 디자인이 나오면 `NaverGeocodingService` 를 붙인다).
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

    /// 지도 조작용.
    let map = NaverMapController()

    /// 권한이 있을 때만 현위치 추적을 켠다. 권한 없이 켜면 SDK 가 빈 점을 들고 헛돈다.
    var isTrackingLocation: Bool { authorization == .authorized }

    // MARK: 의존성

    private let locationService: LocationServicing
    /// 첫 좌표에서 한 번만 카메라를 옮긴다. 이후에는 SDK 의 추적 모드가 맡는다.
    private var hasCenteredOnUser = false

    init(locationService: LocationServicing = LocationService()) {
        self.locationService = locationService
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

    // MARK: -

    private func handleLocationChange() {
        authorization = locationService.authorization
        statusMessage = Self.message(for: locationService.authorization)

        guard locationService.authorization == .authorized else { return }
        locationService.startUpdating()

        guard !hasCenteredOnUser, let coordinate = locationService.lastCoordinate else { return }
        centerOnUser(coordinate)
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

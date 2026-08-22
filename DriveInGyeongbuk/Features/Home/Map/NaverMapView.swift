//
//  NaverMapView.swift
//  DriveInGyeongbuk
//
//  제품 화면용 지도. NAVER Maps iOS SDK(NMapsMap)를 SwiftUI 로 감싼다.
//
//  `Test/NaverMapWebView.swift` 는 WKWebView + Web Dynamic Map 이라 서비스 계층
//  검증용으로만 쓴다. 제품 화면은 현위치 추적·야간 스타일이 필요해서 네이티브를 쓴다.
//
//  컨트롤러 인터페이스는 `NaverMapWebController` 와 같은 이름을 쓰되,
//  이 화면에 필요한 것만 먼저 구현했다.
//    구현됨 : focus / moveToCurrentLocation / showRoute / clear
//
//  ⚠️ NCP 콘솔의 Maps 애플리케이션에 **Mobile Dynamic Map** 서비스가 켜져 있고
//     iOS 번들 ID 가 등록되어 있어야 인증이 통과한다. (Web 서비스 URL 과는 별개다)
//

import Combine
import NMapsMap
import SwiftUI

// MARK: - Controller

/// 지도를 밖에서 조작하기 위한 컨트롤러.
final class NaverMapController: ObservableObject {

    /// 지도 뷰가 만들어졌는지.
    @Published private(set) var isReady = false
    /// 인증 실패 등 지도 자체 오류 메시지.
    @Published private(set) var mapError: String?

    fileprivate weak var mapView: NMFMapView?
    /// 지도가 붙기 전에 들어온 명령을 하나만 기억해 둔다. (카메라 이동은 마지막 것만 의미가 있다)
    private var pendingCameraUpdate: (() -> Void)?
    private var routePath: NMFPath?
    private var endpointMarkers: [NMFMarker] = []

    // MARK: 명령

    /// 지도 중심 이동.
    func focus(on coordinate: NaverCoordinate, zoom: Double = 15, animated: Bool = true) {
        run {
            guard let mapView = self.mapView else { return }
            let update = NMFCameraUpdate(scrollTo: NMGLatLng(lat: coordinate.latitude,
                                                             lng: coordinate.longitude),
                                         zoomTo: zoom)
            update.animation = animated ? .easeIn : .none
            mapView.moveCamera(update)
        }
    }

    /// 현위치 추적 모드로 되돌린다. (사용자가 지도를 끌면 SDK 가 알아서 `.normal` 로 내린다)
    func moveToCurrentLocation() {
        run { self.mapView?.positionMode = .direction }
    }

    /// 주행 시작 시 현재 위치 가까이 확대한 뒤 진행 방향 추적을 켠다.
    func startNavigation(at coordinate: NaverCoordinate, zoom: Double = 18.5) {
        run {
            guard let mapView = self.mapView else { return }
            // 추적 모드 전환이 카메라 축척을 덮어쓸 수 있으므로 먼저 활성화한다.
            mapView.positionMode = .direction
            let update = NMFCameraUpdate(scrollTo: NMGLatLng(lat: coordinate.latitude,
                                                             lng: coordinate.longitude),
                                         zoomTo: zoom)
            update.animation = .easeIn
            mapView.moveCamera(update)
        }
    }

    /// 자동차 경로와 출발·도착 마커를 그리고, 하단 요약 카드 위로 전체 경로를 맞춘다.
    func showRoute(_ route: DrivingRoute,
                   fitsRoute: Bool = true,
                   showsEndpoints: Bool = true) {
        run {
            guard let mapView = self.mapView, route.path.count >= 2 else { return }
            self.removeRouteOverlays()

            let points = route.path.map {
                NMGLatLng(lat: $0.latitude, lng: $0.longitude)
            }
            let path = NMFPath()
            path.path = NMGLineString(points: points)
            path.width = 7
            path.outlineWidth = 2
            // 선택 경로가 겹치는 구간에서도 사용자가 어떤 모드를 골랐는지 즉시 알 수 있게 한다.
            path.color = route.option == .comfortable
                ? UIColor(red: 79 / 255, green: 121 / 255, blue: 1, alpha: 1)
                : UIColor(red: 0, green: 230 / 255, blue: 118 / 255, alpha: 1)
            path.outlineColor = UIColor(red: 14 / 255, green: 31 / 255, blue: 67 / 255, alpha: 1)
            path.mapView = mapView
            self.routePath = path

            if showsEndpoints {
                let start = NMFMarker(position: points[0])
                start.iconImage = NMF_MARKER_IMAGE_GREEN
                start.captionText = "Start"
                start.mapView = mapView

                let goal = NMFMarker(position: points[points.count - 1])
                goal.iconImage = NMF_MARKER_IMAGE_BLUE
                goal.captionText = "Destination"
                goal.mapView = mapView
                self.endpointMarkers = [start, goal]
            }

            if fitsRoute {
                let bounds = NMGLatLngBounds(latLngs: points)
                let update = NMFCameraUpdate(fit: bounds,
                                             paddingInsets: UIEdgeInsets(top: 96,
                                                                         left: 40,
                                                                         bottom: 390,
                                                                         right: 40))
                update.animation = .easeIn
                mapView.moveCamera(update)
            }
        }
    }

    /// 지도 위의 경로 및 출발·도착 마커를 지운다.
    func clear() {
        removeRouteOverlays()
    }

    // MARK: 내부

    fileprivate func attach(_ mapView: NMFMapView) {
        self.mapView = mapView
        isReady = true
        let queued = pendingCameraUpdate
        pendingCameraUpdate = nil
        queued?()
    }

    fileprivate func detach() {
        mapView = nil
        isReady = false
    }

    fileprivate func handleAuthFailure(_ message: String) {
        mapError = message
    }

    private func run(_ command: @escaping () -> Void) {
        guard isReady, mapView != nil else {
            pendingCameraUpdate = command
            return
        }
        command()
    }

    private func removeRouteOverlays() {
        routePath?.mapView = nil
        routePath = nil
        endpointMarkers.forEach { $0.mapView = nil }
        endpointMarkers = []
    }
}

// MARK: - SwiftUI View

/// 컨트롤 없이 지도만 보여 주는 뷰. 검색 필드·버튼은 SwiftUI 쪽에서 얹는다.
struct NaverMapView: UIViewRepresentable {

    @ObservedObject var controller: NaverMapController

    /// 현위치 추적 모드. 권한이 없으면 `.disabled` 로 두어야 SDK 가 헛돌지 않는다.
    var positionMode: NMFMyPositionMode = .disabled
    /// 주행 모드가 자체적으로 카메라를 옮긴 뒤 적용할 근거리 줌. 미리보기 화면에서는 `nil`.
    var navigationZoom: Double? = nil
    /// 어두운 지도를 쓸지. 피그마 시안이 다크라 기본은 다크로 두고, 라이트 모드에서는 밝은 지도를 쓴다.
    var isNightMode: Bool = true
    /// 로고·저작권 표시가 검색 필드나 탭바에 가리지 않도록 띄울 여백.
    var logoMargin: UIEdgeInsets = .zero

    func makeUIView(context: Context) -> NMFNaverMapView {
        let view = NMFNaverMapView(frame: .zero)

        // 시안에 없는 기본 컨트롤은 모두 끈다. (로고는 이용약관상 끌 수 없다)
        view.showCompass = false
        view.showScaleBar = false
        view.showZoomControls = false
        view.showLocationButton = false
        view.showIndoorLevelPicker = false

        let mapView = view.mapView
        // 내비 타입이 도로 위계를 굵기로 구분해 줘서 주행 화면에 맞는다.
        mapView.mapType = .navi
        mapView.logoAlign = .leftBottom
        mapView.locale = Locale.current.identifier

        controller.attach(mapView)
        return view
    }

    func updateUIView(_ uiView: NMFNaverMapView, context: Context) {
        let mapView = uiView.mapView
        if mapView.isNightModeEnabled != isNightMode {
            mapView.isNightModeEnabled = isNightMode
        }
        if mapView.logoMargin != logoMargin {
            mapView.logoMargin = logoMargin
        }

        // 추적 모드는 "현재 값이 다르면 되돌린다"가 아니라 "요청 값이 바뀔 때만 적용한다".
        // 사용자가 지도를 끌면 SDK 가 스스로 `.normal` 로 내리는데, 현재 값과 비교하면
        // 다음 갱신 때 `.direction` 으로 도로 올려 버려서 카메라를 뺏게 된다.
        if context.coordinator.appliedPositionMode != positionMode {
            context.coordinator.appliedPositionMode = positionMode
            mapView.positionMode = positionMode
        }

        if context.coordinator.appliedNavigationZoom != navigationZoom {
            context.coordinator.appliedNavigationZoom = navigationZoom
            if let navigationZoom {
                // `.direction` 전환이 비동기로 전체 경로 카메라를 덮어쓸 수 있어
                // 추적 카메라가 자리 잡은 다음 축척만 다시 강제한다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak mapView] in
                    guard let mapView else { return }
                    let update = NMFCameraUpdate(zoomTo: navigationZoom)
                    update.animation = .easeIn
                    mapView.moveCamera(update)
                }
            }
        }
    }

    static func dismantleUIView(_ uiView: NMFNaverMapView, coordinator: Coordinator) {
        // 추적을 켜 둔 채로 화면이 사라지면 SDK 가 계속 위치를 받아 배터리를 먹는다.
        uiView.mapView.positionMode = .disabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    final class Coordinator {
        let controller: NaverMapController
        /// 마지막으로 지도에 넣어 준 추적 모드. `updateUIView` 참고.
        var appliedPositionMode: NMFMyPositionMode?
        var appliedNavigationZoom: Double?

        init(controller: NaverMapController) {
            self.controller = controller
        }

        deinit {
            controller.detach()
        }
    }
}

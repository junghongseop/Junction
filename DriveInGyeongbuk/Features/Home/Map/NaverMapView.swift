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
//    구현됨 : focus / moveToCurrentLocation / clear
//    TODO   : showMarkers / showRoute / highlight — 경로 안내 화면을 붙일 때 채운다
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

    /// 지도 위에 그린 것들을 모두 지운다. 지금은 그리는 게 없어서 할 일이 없다.
    func clear() {
        // TODO: 마커·폴리라인을 그리기 시작하면 여기서 걷어낸다.
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
}

// MARK: - SwiftUI View

/// 컨트롤 없이 지도만 보여 주는 뷰. 검색 필드·버튼은 SwiftUI 쪽에서 얹는다.
struct NaverMapView: UIViewRepresentable {

    @ObservedObject var controller: NaverMapController

    /// 현위치 추적 모드. 권한이 없으면 `.disabled` 로 두어야 SDK 가 헛돌지 않는다.
    var positionMode: NMFMyPositionMode = .disabled
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

        init(controller: NaverMapController) {
            self.controller = controller
        }

        deinit {
            controller.detach()
        }
    }
}

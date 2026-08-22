//
//  NaverMapWebView.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] 네이버 지도를 화면에 띄우기 위한 최소 구현.
//
//  Web Dynamic Map(JavaScript API v3)을 WKWebView 로 감싼다.
//  외부 SDK 의존성이 없어서 클론 직후 바로 빌드/실행되는 것이 장점이라
//  서비스 계층 검증용으로 이 방식을 골랐다.
//  실제 제품 화면은 나중에 NAVER Maps iOS SDK(NMapsMap)로 교체해도 되고,
//  이 파일의 `NaverMapWebController` 인터페이스를 그대로 맞춰주면 된다.
//
//  ⚠️ NCP 콘솔 > Web Dynamic Map 의 "Web 서비스 URL" 에
//     `AppConfig.naverMapWebServiceURL` 과 같은 도메인(기본값 https://localhost)을
//     등록해 두어야 인증이 통과한다.
//

import Combine
import SwiftUI
import WebKit

// MARK: - Controller

/// 지도에 그릴 내용을 Swift 쪽에서 명령하기 위한 컨트롤러.
final class NaverMapWebController: ObservableObject {

    /// 지도 스크립트 로딩이 끝났는지.
    @Published private(set) var isReady = false
    /// 인증 실패 등 지도 자체 오류 메시지.
    @Published private(set) var mapError: String?
    /// 지도에서 마지막으로 탭한 좌표.
    @Published var lastTappedCoordinate: NaverCoordinate?

    /// 지도를 탭했을 때 불린다. (SwiftUI 관찰 체인을 타지 않고 바로 알림)
    var onMapTap: ((NaverCoordinate) -> Void)?

    fileprivate weak var webView: WKWebView?
    /// 지도가 준비되기 전에 들어온 명령을 모아 둔다.
    private var pendingScripts: [String] = []

    // MARK: 명령

    /// 지도 중심 이동.
    func focus(on coordinate: NaverCoordinate, zoom: Int = 15) {
        evaluate("window.appBridge.focus(\(coordinate.latitude), \(coordinate.longitude), \(zoom));")
    }

    /// 마커만 찍는다. (주소 검색 결과 확인용)
    func showMarkers(_ markers: [Marker], fitBounds: Bool = true) {
        guard let json = Self.jsonString(markers.map(\.jsonObject)) else { return }
        evaluate("window.appBridge.setMarkers(\(json), \(fitBounds));")
    }

    /// 경로 폴리라인 + 출발/도착 마커를 그린다.
    func showRoute(_ route: DrivingRoute) {
        let path = route.path.map { [$0.latitude, $0.longitude] }
        guard let pathJSON = Self.jsonString(path) else { return }

        let markers: [Marker] = [
            Marker(coordinate: route.start, title: "출발", color: "#1B8A4B"),
            Marker(coordinate: route.goal, title: "도착", color: "#D1345B")
        ]
        guard let markersJSON = Self.jsonString(markers.map(\.jsonObject)) else { return }

        evaluate("window.appBridge.setRoute(\(pathJSON), \(markersJSON));")
    }

    /// 특정 안내 지점을 강조 표시한다.
    func highlight(_ coordinate: NaverCoordinate, label: String) {
        let escaped = Self.escapeForJavaScript(label)
        evaluate("window.appBridge.highlight(\(coordinate.latitude), \(coordinate.longitude), \"\(escaped)\");")
    }

    /// 지도 위에 그린 것들을 모두 지운다.
    func clear() {
        evaluate("window.appBridge.clear();")
    }

    // MARK: 내부

    fileprivate func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    fileprivate func handleReady() {
        isReady = true
        mapError = nil
        let queued = pendingScripts
        pendingScripts.removeAll()
        queued.forEach(evaluate)
    }

    fileprivate func handleError(_ message: String) {
        mapError = message
    }

    private func evaluate(_ script: String) {
        guard isReady, let webView else {
            pendingScripts.append(script)
            return
        }
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.mapError = "지도 스크립트 오류: \(error.localizedDescription)"
            }
        }
    }

    // MARK: 유틸

    struct Marker {
        var coordinate: NaverCoordinate
        var title: String
        var color: String

        var jsonObject: [String: Any] {
            ["lat": coordinate.latitude,
             "lng": coordinate.longitude,
             "title": title,
             "color": color]
        }
    }

    private static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func escapeForJavaScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - SwiftUI View

struct NaverMapWebView: UIViewRepresentable {

    @ObservedObject var controller: NaverMapWebController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: Coordinator.bridgeName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false

        controller.attach(webView)
        webView.loadHTMLString(Self.makeHTML(clientID: AppConfig.naverMapClientID),
                               baseURL: AppConfig.naverMapWebServiceURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 그리기는 컨트롤러의 명령으로만 이루어진다.
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController
            .removeScriptMessageHandler(forName: Coordinator.bridgeName)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {

        static let bridgeName = "naverMapBridge"

        private let controller: NaverMapWebController

        init(controller: NaverMapWebController) {
            self.controller = controller
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any],
                  let name = payload["name"] as? String else { return }
            let body = payload["body"] as? [String: Any] ?? [:]

            switch name {
            case "ready":
                controller.handleReady()

            case "authFailure":
                controller.handleError(body["message"] as? String ?? "지도 인증에 실패했습니다.")

            case "mapClick":
                if let lat = body["lat"] as? Double, let lng = body["lng"] as? Double {
                    let coordinate = NaverCoordinate(latitude: lat, longitude: lng)
                    controller.lastTappedCoordinate = coordinate
                    controller.onMapTap?(coordinate)
                }

            case "log":
                #if DEBUG
                print("[NaverMapWebView] \(body["message"] as? String ?? "")")
                #endif

            default:
                break
            }
        }
    }
}

// MARK: - HTML

private extension NaverMapWebView {

    static func makeHTML(clientID: String) -> String {
        htmlTemplate.replacingOccurrences(of: "__CLIENT_ID__", with: clientID)
    }

    static let htmlTemplate = #"""
    <!DOCTYPE html>
    <html lang="ko">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
      <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #eef1f4; }
        #map { width: 100%; height: 100%; }
        .pin {
          display: inline-block; padding: 3px 8px; border-radius: 12px;
          font: 600 12px -apple-system, system-ui, sans-serif; color: #fff;
          white-space: nowrap; box-shadow: 0 1px 4px rgba(0,0,0,.35);
        }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <script>
        var CLIENT_ID = "__CLIENT_ID__";
        var map = null, polyline = null, markers = [], highlightMarker = null;

        function post(name, body) {
          try {
            window.webkit.messageHandlers.naverMapBridge.postMessage({ name: name, body: body || {} });
          } catch (e) { /* 브리지가 없으면 무시 */ }
        }

        window.onerror = function (message) { post("log", { message: String(message) }); };

        // 네이버 지도 SDK 가 인증 실패 시 호출하는 전역 콜백.
        window.navermap_authFailure = function () {
          post("authFailure", {
            message: "네이버 지도 인증에 실패했습니다. Client ID 와 NCP 콘솔의 Web 서비스 URL 등록을 확인하세요."
          });
        };

        function clearOverlays() {
          if (polyline) { polyline.setMap(null); polyline = null; }
          markers.forEach(function (m) { m.setMap(null); });
          markers = [];
          if (highlightMarker) { highlightMarker.setMap(null); highlightMarker = null; }
        }

        function makeMarker(spec) {
          return new naver.maps.Marker({
            map: map,
            position: new naver.maps.LatLng(spec.lat, spec.lng),
            title: spec.title,
            icon: {
              content: '<span class="pin" style="background:' + (spec.color || "#2E7DFF") + '">'
                     + (spec.title || "") + '</span>',
              anchor: new naver.maps.Point(10, 10)
            }
          });
        }

        function fitTo(latLngs) {
          if (!latLngs.length) { return; }
          var bounds = new naver.maps.LatLngBounds(latLngs[0], latLngs[0]);
          latLngs.forEach(function (p) { bounds.extend(p); });
          map.fitBounds(bounds, { top: 60, right: 60, bottom: 60, left: 60 });
        }

        window.appBridge = {
          focus: function (lat, lng, zoom) {
            if (!map) { return; }
            map.setCenter(new naver.maps.LatLng(lat, lng));
            map.setZoom(zoom || 15);
          },

          setMarkers: function (specs, shouldFit) {
            if (!map) { return; }
            clearOverlays();
            var points = [];
            specs.forEach(function (spec) {
              markers.push(makeMarker(spec));
              points.push(new naver.maps.LatLng(spec.lat, spec.lng));
            });
            if (shouldFit && points.length > 1) { fitTo(points); }
            else if (shouldFit && points.length === 1) { map.setCenter(points[0]); map.setZoom(15); }
          },

          setRoute: function (path, markerSpecs) {
            if (!map) { return; }
            clearOverlays();
            var latLngs = path.map(function (p) { return new naver.maps.LatLng(p[0], p[1]); });
            if (latLngs.length) {
              polyline = new naver.maps.Polyline({
                map: map, path: latLngs,
                strokeColor: "#2E7DFF", strokeOpacity: 0.9, strokeWeight: 6
              });
            }
            (markerSpecs || []).forEach(function (spec) { markers.push(makeMarker(spec)); });
            fitTo(latLngs.length ? latLngs : (markerSpecs || []).map(function (s) {
              return new naver.maps.LatLng(s.lat, s.lng);
            }));
          },

          highlight: function (lat, lng, label) {
            if (!map) { return; }
            if (highlightMarker) { highlightMarker.setMap(null); }
            highlightMarker = makeMarker({ lat: lat, lng: lng, title: label, color: "#F5A524" });
            map.setCenter(new naver.maps.LatLng(lat, lng));
            map.setZoom(16);
          },

          clear: function () { clearOverlays(); }
        };

        function initMap() {
          if (!window.naver || !window.naver.maps) {
            post("authFailure", { message: "naver.maps 객체를 찾을 수 없습니다." });
            return;
          }
          // 초기 화면은 경상북도청 부근.
          map = new naver.maps.Map("map", {
            center: new naver.maps.LatLng(36.5760, 128.5056),
            zoom: 9,
            scaleControl: true,
            logoControl: true,
            mapDataControl: false,
            zoomControl: false
          });
          naver.maps.Event.addListener(map, "click", function (e) {
            post("mapClick", { lat: e.coord.lat(), lng: e.coord.lng() });
          });
          post("ready", {});
        }

        // 신규 키는 ncpKeyId, 이전에 발급된 키는 ncpClientId 를 쓴다. 순서대로 시도한다.
        function loadSDK(paramName, onFail) {
          var script = document.createElement("script");
          script.src = "https://oapi.map.naver.com/openapi/v3/maps.js?"
                     + paramName + "=" + encodeURIComponent(CLIENT_ID);
          script.onload = initMap;
          script.onerror = onFail;
          document.head.appendChild(script);
        }

        if (!CLIENT_ID) {
          post("authFailure", { message: "Client ID 가 비어 있습니다. Config/Config.xcconfig 를 확인하세요." });
        } else {
          loadSDK("ncpKeyId", function () {
            loadSDK("ncpClientId", function () {
              post("authFailure", { message: "지도 스크립트를 불러오지 못했습니다. 네트워크와 키를 확인하세요." });
            });
          });
        }
      </script>
    </body>
    </html>
    """#
}

//
//  DriveInGyeongbukApp.swift
//  DriveInGyeongbuk
//
//  Created by 정홍섭 on 8/22/26.
//

import NMapsMap
import SwiftUI

@main
struct DriveInGyeongbukApp: App {

    init() {
        Self.configureNaverMapsSDK()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }

    /// 네이티브 지도 SDK 에 NCP 키를 넘긴다.
    ///
    /// Info.plist 의 `NMFNcpKeyId` 로도 줄 수 있지만, 키는 xcconfig 에서 들어오므로
    /// 값이 비면 `"$(Naver_Map_Client_ID)"` 가 그대로 남는다. 그 상태로 SDK 에 넘기면
    /// 인증 실패 팝업만 뜨므로, 이미 그 경우를 걸러 주는 `AppConfig` 를 거쳐 코드로 넣는다.
    private static func configureNaverMapsSDK() {
        guard AppConfig.hasNaverMapClientID else { return }
        NMFAuthManager.shared().ncpKeyId = AppConfig.naverMapClientID
    }
}

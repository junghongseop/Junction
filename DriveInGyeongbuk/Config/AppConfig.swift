//
//  AppConfig.swift
//  DriveInGyeongbuk
//
//  Created by 정홍섭 on 8/22/26.
//
//  키는 저장소에 커밋하지 않는다.
//  `Config/Config.xcconfig` (gitignore 대상) → Info.plist → 여기 순서로 주입된다.
//  로컬 세팅 방법은 `Config/Config.xcconfig.sample` 참고.
//

import Foundation

enum AppConfig {

    /// NAVER Cloud Platform 애플리케이션의 Client ID (= API Key ID).
    /// 지도 표시(Web Dynamic Map / Mobile SDK)와 REST 인증 헤더에 모두 쓰인다.
    static let naverMapClientID: String = infoValue(
        "Naver_Map_Client_ID",
        "Naver_Map_API_Key_ID",
        "Naver_Map_API_Key"      // 키를 하나만 넣어 둔 기존 설정 호환
    )

    /// NAVER Cloud Platform 애플리케이션의 Client Secret (= API Key).
    /// Geocoding / Directions 같은 REST API 호출에 필요하다.
    static let naverMapClientSecret: String = infoValue(
        "Naver_Map_Client_Secret",
        "Naver_Map_API_Key_Secret"
    )

    /// 지도를 표시할 웹 문서의 기준 URL.
    ///
    /// Web Dynamic Map 은 요청 도메인을 NCP 콘솔에 등록된 서비스 URL 과 대조한다.
    /// 여기에 적은 값과 같은 도메인을 콘솔의 `Web 서비스 URL` 에 등록해 두어야 한다.
    static let naverMapWebServiceURL = URL(string: "https://localhost")!

    /// REST API 키가 준비되었는지.
    static var hasNaverMapsRESTCredentials: Bool {
        !naverMapClientID.isEmpty && !naverMapClientSecret.isEmpty
    }

    /// 지도 표시용 키가 준비되었는지.
    static var hasNaverMapClientID: Bool {
        !naverMapClientID.isEmpty
    }

    // MARK: -

    /// Info.plist 에서 첫 번째로 값이 채워진 키를 읽는다.
    private static func infoValue(_ keys: String...) -> String {
        for key in keys {
            guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // xcconfig 변수가 비어 있으면 "$(Naver_Map_Client_ID)" 가 그대로 남는 경우가 있다.
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        return ""
    }
}

/// 기존 코드 호환용.
@available(*, deprecated, renamed: "AppConfig.naverMapClientID")
var NaverMapAPIKey: String { AppConfig.naverMapClientID }

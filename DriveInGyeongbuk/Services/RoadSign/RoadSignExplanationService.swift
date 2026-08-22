//
//  RoadSignExplanationService.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  인식된 한국어 표지판 / 한국어 경로 안내 문구를 외국인이 이해할 수 있는
//  설명으로 바꿔 준다. 이 앱의 핵심 가치가 걸린 부분.
//

import Foundation

/// 외국인 사용자를 위한 표지판 설명.
struct RoadSignExplanation: Identifiable, Hashable {
    var id = UUID()

    /// 한국어 원문.
    var korean: String
    /// 한 줄 번역.
    var translation: String
    /// "무엇을 해야 하는지" 한 문장.
    var whatToDo: String
    /// 배경 설명(한국 도로 규칙 등). 없을 수 있다.
    var detail: String?
    var locale: Locale
}

protocol RoadSignExplaining {
    /// 지원 언어.
    var supportedLocales: [Locale] { get }

    /// 인식된 표지판을 설명한다.
    func explain(_ sign: RoadSign, in locale: Locale) async throws -> RoadSignExplanation

    /// 네이버 경로 안내 문구(한국어)를 설명한다.
    /// 예) "'포항' 방면으로 우측 방향" → "Keep right toward Pohang"
    func explain(instruction: String, in locale: Locale) async throws -> RoadSignExplanation
}

// MARK: - Stub

/// TODO: 온디바이스 사전(자주 나오는 문구) + 원격 번역/LLM 폴백의 2단 구성.
struct RoadSignExplanationService: RoadSignExplaining {

    var supportedLocales: [Locale] {
        // TODO: 실제 지원 언어로 교체 (en, ja, zh-Hans, vi ...).
        [Locale(identifier: "en")]
    }

    init() {}

    func explain(_ sign: RoadSign, in locale: Locale) async throws -> RoadSignExplanation {
        // TODO: sign.category + koreanText 기반 설명 생성.
        throw ServiceNotImplementedError(service: "RoadSignExplanationService.explain(_:in:)")
    }

    func explain(instruction: String, in locale: Locale) async throws -> RoadSignExplanation {
        // TODO: 지명/방면 토큰을 분리해 번역 품질을 높인다.
        throw ServiceNotImplementedError(service: "RoadSignExplanationService.explain(instruction:in:)")
    }
}

/// 아직 구현되지 않은 서비스를 호출했을 때 던지는 에러.
struct ServiceNotImplementedError: Error, LocalizedError {
    var service: String
    var errorDescription: String? { "\(service) 는 아직 구현되지 않았습니다." }
}

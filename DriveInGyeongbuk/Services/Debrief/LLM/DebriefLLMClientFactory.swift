//
//  DebriefLLMClientFactory.swift
//  DriveInGyeongbuk
//
//  어떤 LLM 클라이언트를 쓸지 고르는 곳.
//
//  키가 있으면 Gemini, 없으면 규칙 기반 목이다. **키가 없다고 기능이 사라지지는 않는다** —
//  안내 문구가 좀 더 뻣뻣해질 뿐, 감지·주제 선정·화면은 그대로 돌아간다. 데모 도중
//  네트워크가 죽어도 Debrief 가 빈 화면이 되지 않게 하려는 것이다.
//
//  `DebriefService` 는 여기서 만든 클라이언트가 실패하면 `fallback` 으로 한 번 더 시도한다.
//

import Foundation

enum DebriefLLMClientFactory {

    /// 지금 설정으로 쓸 수 있는 최선의 클라이언트.
    static func makeDefault() -> DebriefLLMClient {
        AppConfig.hasGeminiCredentials ? GeminiDebriefLLMClient() : MockDebriefLLMClient()
    }

    /// 위가 실패했을 때 쓰는 대체. 네트워크도 키도 필요 없다.
    static func makeFallback() -> DebriefLLMClient {
        // 목 클라이언트의 인위적 지연은 여기서 필요 없다. 이미 한 번 기다린 뒤다.
        MockDebriefLLMClient(simulatedDelaySeconds: 0)
    }

    /// 지금 실제로 LLM 을 태우는지. 개발자 화면 표시용.
    static var usesLiveLLM: Bool { AppConfig.hasGeminiCredentials }
}

//
//  MockDebriefLLMClient.swift
//  DriveInGyeongbuk
//
//  LLM 없이 Debrief 전 과정을 돌리기 위한 구현.
//
//  왜 있어야 하는가
//    · 키가 없거나 네트워크가 죽어도 기능이 통째로 사라지면 안 된다.
//    · 미리보기·개발자 메뉴에서 화면을 보려고 매번 토큰을 태울 이유가 없다.
//    · 무엇보다, 감지 계층과 화면이 LLM 없이도 맞는지 따로 확인할 수 있어야 한다.
//
//  고르는 규칙은 실제 LLM 에게 시키는 것과 같은 원칙을 규칙으로 굳힌 것이다 —
//  처음 온 사람에게 낯설 것 · 다음에 바로 써먹을 수 있을 것 순.
//  설명 문장은 **검증된 콘텐츠에서 그대로** 가져온다. 여기서도 사실을 만들지 않는다.
//

import Foundation

nonisolated struct MockDebriefLLMClient: DebriefLLMClient {

    /// 네트워크 왕복을 흉내 내는 지연(초). 로딩 화면을 확인하려고 둔다.
    var simulatedDelaySeconds: Double = 0.6

    init(simulatedDelaySeconds: Double = 0.6) {
        self.simulatedDelaySeconds = simulatedDelaySeconds
    }

    func makeReport(for request: DebriefRequest) async throws -> DebriefReport {

        if simulatedDelaySeconds > 0 {
            try? await Task.sleep(for: .seconds(simulatedDelaySeconds))
        }

        let ranked = request.events.sorted { priority(of: $0) > priority(of: $1) }
        var lessons: [DebriefReport.Lesson] = []
        var usedTopics: Set<DebriefTopicID> = []
        var usedKinds: Set<DriveEvent.Kind> = []

        for event in ranked {
            guard lessons.count < request.maximumLessonCount else { break }

            // 같은 종류의 사건은 한 번만 설명한다.
            // 과속 구간이 셋이어도 카드 세 장을 만들면 같은 말을 세 번 하는 꼴이 된다.
            guard usedKinds.insert(event.kind).inserted else { continue }

            // 사건이 가리키는 주제 중, 아직 안 쓴 것 하나를 고른다.
            guard let topic = event.relatedTopicIDs
                .first(where: { !usedTopics.contains($0) })
                .flatMap({ id in request.availableTopics.first { $0.id == id } }) else { continue }

            usedTopics.insert(topic.id)
            lessons.append(DebriefReport.Lesson(
                eventID: event.id,
                topicID: topic.id,
                title: title(for: event, topic: topic),
                explanation: explanation(for: event, topic: topic, driver: request.driver),
                reason: "Mock client: highest-priority unexplained event of kind \(event.kind.rawValue)."
            ))
        }

        return DebriefReport(summary: summary(for: request, lessonCount: lessons.count),
                             lessons: lessons)
    }

    // MARK: - 우선순위

    /// 높을수록 먼저 설명한다.
    ///
    /// 실제 LLM 에게 주는 지시와 같은 기준이다: 지금 바로 행동으로 옮길 수 있는 것,
    /// 그리고 한국 도로가 처음이면 모를 만한 것.
    private func priority(of event: DriveEvent) -> Int {
        switch event.kind {
        case .longStop:
            // 금지구간에 실제로 섰다면 가장 급하다.
            return event.fact("insideRestrictedZone") == "true" ? 100 : 40
        case .sustainedSpeeding:
            // 제한속도가 떨어진 직후였다면 설명할 값어치가 훨씬 크다.
            return event.fact("startedRightAfterLimitDrop") == "true" ? 90 : 70
        case .tollGatePassed:
            return 60
        case .speedLimitChange:
            return 50
        }
    }

    // MARK: - 문장

    /// 카드 제목.
    ///
    /// **주제로 먼저 가른다.** 사건 종류만으로 정하면, 서로 다른 주제를 고른 카드 두 장이
    /// 같은 제목을 달고 나란히 서는 일이 생긴다 (실제로 그렇게 나왔다).
    private func title(for event: DriveEvent, topic: DebriefTopic) -> String {
        switch topic.id {
        case .speedLimitChange:
            if event.kind == .speedLimitChange, let count = event.fact("changeCount") {
                return "Speed limits changed \(count) times"
            }
            return "Watch for speed limit changes"
        case .speedingRule:
            return "Keeping to the posted limit"
        case .trafficCamera:
            return "Where the cameras are"
        case .tollGate:
            return "You passed a toll gate"
        case .unpaidToll:
            return "Checking today's toll"
        case .noStoppingZone:
            return "You stopped where stopping is limited"
        case .noParkingZone:
            return event.fact("insideRestrictedZone") == "true"
                ? "You stopped where stopping is limited"
                : "Where you can park"
        case .yellowLine:
            return "Yellow lines down the middle"
        case .schoolZone:
            return "School zones"
        }
    }

    /// 사건 한 줄 + 검증된 사실 두 문장 + 다음 행동.
    ///
    /// 실제 LLM 이 하는 "개인화된 재서술"의 자리를 규칙으로 채운 것이라 문장이 좀 뻣뻣하다.
    /// 사실 자체는 실제 LLM 을 붙였을 때와 동일하다 — 둘 다 `topic.facts` 안에서만 말한다.
    private func explanation(for event: DriveEvent,
                             topic: DebriefTopic,
                             driver: DebriefRequest.Driver) -> String {
        var sentences: [String] = [event.summary]
        sentences.append(contentsOf: topic.facts.prefix(2))
        if let actionNote = topic.actionNote {
            sentences.append(actionNote)
        }
        return sentences.joined(separator: " ")
    }

    /// 화면 맨 위 한 문장.
    ///
    /// 개수를 여기서 세지 않는다. 바로 아래에 "2 things to know" 라벨이 따로 있어서,
    /// 세면 같은 말을 두 번 하게 된다. 실제 LLM 프롬프트에도 같은 제약을 건다.
    private func summary(for request: DebriefRequest, lessonCount: Int) -> String {
        guard lessonCount > 0 else {
            return "Nothing stood out on this drive. Nicely done."
        }
        return request.driver.isFirstDriveInKorea
            ? "Your first drive in Gyeongbuk is complete."
            : "Drive complete."
    }
}

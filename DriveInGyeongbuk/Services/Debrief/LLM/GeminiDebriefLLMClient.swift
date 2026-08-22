//
//  GeminiDebriefLLMClient.swift
//  DriveInGyeongbuk
//
//  `DebriefLLMClient` 의 Gemini 구현. Debrief 한 건당 **API 호출 1회**다.
//
//  키에 대해
//    키는 `Config.xcconfig` → Info.plist → `AppConfig.geminiAPIKey` 로 들어온다.
//    즉 **앱 번들 안에 문자열로 남는다.** IPA 를 풀면 꺼낼 수 있다.
//    해커톤/데모까지는 이걸로 충분하지만, 실제 배포에서는 서버를 한 겹 두고 앱은
//    그 서버만 부르게 바꿔야 한다. 그때 갈아 끼울 자리는 이 클래스 하나다
//    (`DebriefLLMClient` 를 구현한 다른 타입으로 바꾸면 나머지는 그대로다).
//
//  응답을 믿지 않는 부분
//    스키마로 `topicId` / `eventId` 를 실제 값의 enum 으로 좁혀 두었지만, 그것과 별개로
//    받은 뒤에도 한 번 더 거른다. 모델이 스키마를 어겼거나 API 가 스키마를 무시했을 때
//    화면에 이상한 게 올라가는 것보다 카드 한 장이 없는 편이 낫다.
//

import Foundation

struct GeminiDebriefLLMClient: DebriefLLMClient {

    private let runner: GeminiRequestRunner
    private let configuration: GeminiConfiguration

    init(configuration: GeminiConfiguration = .default,
         httpClient: GeminiHTTPClient = URLSessionGeminiHTTPClient()) {
        self.configuration = configuration
        self.runner = GeminiRequestRunner(configuration: configuration, httpClient: httpClient)
    }

    var hasCredentials: Bool { configuration.hasCredentials }

    // MARK: -

    func makeReport(for request: DebriefRequest) async throws -> DebriefReport {

        guard configuration.hasCredentials else { throw GeminiError.missingAPIKey }

        // 고를 게 없으면 부르지 않는다. 토큰도 아깝고, 빈 목록을 주면 모델이
        // 억지로 뭔가를 만들어 내려 한다.
        guard !request.events.isEmpty, !request.availableTopics.isEmpty else {
            return DebriefReport(summary: "Nothing stood out on this drive. Nicely done.", lessons: [])
        }

        let body = try makeRequestBody(for: request)
        let urlRequest = try runner.makeRequest(body: body)
        let response = try await runner.send(urlRequest)

        // 잘린 응답을 파싱해 봐야 "JSON 이 이상하다" 는 말밖에 못 듣는다. 먼저 거른다.
        if response.isIncomplete {
            throw GeminiError.truncated(outputTokens: response.usage?.totalOutputTokens,
                                        limit: configuration.maxOutputTokens)
        }

        guard let text = response.outputText else {
            throw GeminiError.emptyResponse(response.errorMessage ?? "status: \(response.status ?? "unknown")")
        }

        let report = try decodeReport(from: text)
        return sanitize(report, against: request)
    }

    // MARK: - 요청 만들기

    private func makeRequestBody(for request: DebriefRequest) throws -> GeminiInteractionRequestDTO {

        let schema = DebriefPrompt.responseSchema(for: request)

        let input: String
        let systemInstruction: String?

        if configuration.sendsSystemInstructionSeparately {
            input = try DebriefPrompt.input(for: request)
            systemInstruction = DebriefPrompt.systemInstruction(
                language: request.driver.language,
                maximumLessonCount: request.maximumLessonCount
            )
        } else {
            input = try DebriefPrompt.combinedInput(for: request)
            systemInstruction = nil
        }

        return GeminiInteractionRequestDTO(
            model: configuration.model,
            input: input,
            systemInstruction: systemInstruction,
            responseFormat: .init(schema: schema),
            generationConfig: .init(maxOutputTokens: configuration.maxOutputTokens,
                                    thinkingLevel: configuration.thinkingLevel),
            // 주행 기록이 남는 걸 원치 않고, 이어 붙일 대화도 없다.
            store: false
        )
    }

    // MARK: - 응답 읽기

    private func decodeReport(from text: String) throws -> DebriefReport {
        guard let data = extractJSONObject(from: text).data(using: .utf8) else {
            throw GeminiError.decoding("응답을 UTF-8 로 읽지 못했습니다.")
        }
        do {
            return try JSONDecoder().decode(DebriefReport.self, from: data)
        } catch {
            throw GeminiError.decoding("\(error.localizedDescription) / 원문: \(text.prefix(300))")
        }
    }

    /// 본문에서 JSON 객체만 떼어 낸다.
    ///
    /// `response_format` 을 걸었으면 순수 JSON 이 와야 하지만, 모델이 ```json 펜스나
    /// 짧은 머리말을 붙이는 경우가 드물게 있다. 그것 때문에 전체가 실패하면 손해라서
    /// 첫 `{` 부터 마지막 `}` 까지만 남긴다.
    private func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end else { return trimmed }
        return String(trimmed[start...end])
    }

    // MARK: - 응답 거르기

    /// 우리가 준 적 없는 값을 골라 왔으면 그 카드를 버린다.
    ///
    /// `DebriefService` 도 주제가 저장소에 있는지 다시 확인하지만, 그건 "화면에 못 그리니까"
    /// 버리는 것이고 여기는 "우리가 준 목록에 없으니까" 버리는 것이다. 둘은 다른 검사다 —
    /// 카탈로그에는 있지만 이번 요청에 넣지 않은 주제를 골라 오는 경우가 여기서 걸린다.
    private func sanitize(_ report: DebriefReport, against request: DebriefRequest) -> DebriefReport {

        let allowedTopics = Set(request.availableTopics.map(\.id))
        let allowedEvents = Set(request.events.map(\.id))

        var seenTopics: Set<DebriefTopicID> = []

        let lessons = report.lessons.compactMap { lesson -> DebriefReport.Lesson? in
            guard allowedTopics.contains(lesson.topicID) else { return nil }
            // 같은 주제를 두 번 설명하지 않는다.
            guard seenTopics.insert(lesson.topicID).inserted else { return nil }

            var lesson = lesson
            // 없는 사건을 가리키면 연결만 끊는다. 설명 자체는 검증된 콘텐츠에서 나온 것이라 살린다.
            if let eventID = lesson.eventID, !allowedEvents.contains(eventID) {
                lesson.eventID = nil
            }
            lesson.title = lesson.title.trimmingCharacters(in: .whitespacesAndNewlines)
            lesson.explanation = lesson.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lesson.title.isEmpty, !lesson.explanation.isEmpty else { return nil }
            return lesson
        }

        return DebriefReport(
            summary: report.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            lessons: Array(lessons.prefix(request.maximumLessonCount))
        )
    }
}

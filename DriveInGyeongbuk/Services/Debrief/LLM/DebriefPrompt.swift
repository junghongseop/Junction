//
//  DebriefPrompt.swift
//  DriveInGyeongbuk
//
//  LLM 에게 보내는 것 전부 — 지시문 · 입력 · 응답 스키마.
//
//  한 곳에 모아 둔 이유
//    프롬프트가 클라이언트 코드에 섞이면 "무엇을 시켰는지" 를 읽으려고 네트워크 코드까지
//    헤집어야 한다. 이 기능은 **LLM 의 권한 범위를 좁히는 것 자체가 설계**라서,
//    그 경계가 한 파일 안에서 통째로 보여야 한다.
//
//  경계 요약
//    LLM 이 하는 일 : 감지된 사건 중 무엇을 설명할지 고르고, 준비된 문장을 다시 쓴다.
//    LLM 이 못 하는 일: 사건 판단, 위반 여부 판정, 법규·과태료·연락처 생성.
//
//  마지막 방어선은 스키마다. `topicId` / `eventId` 를 **이번 요청에 실제로 들어 있는
//  값들의 enum** 으로 만들어서, 없는 주제나 없는 사건을 지어내는 것 자체가 불가능하게 한다.
//

import Foundation

nonisolated enum DebriefPrompt {

    // MARK: - 지시문

    /// 시스템 지시문.
    ///
    /// 톤 규칙보다 "하면 안 되는 것" 을 길게 쓴 이유는, 이 기능에서 생길 수 있는 최악의
    /// 결과가 "문장이 어색한 것" 이 아니라 **없는 법을 지어내 외국인에게 알려 주는 것**
    /// 이기 때문이다.
    static func systemInstruction(language: String, maximumLessonCount: Int) -> String {
        """
        You are the debrief writer inside a navigation app used by foreign drivers in \
        Gyeongsangbuk-do, South Korea.

        The drive is already over. Rule-based code in the app has already decided what happened \
        during it. You are not being asked to analyse raw GPS, and you will not be shown any. \
        Your job has exactly two parts:

        1. CHOOSE which of the detected events are worth explaining to this particular driver.
        2. REWRITE the prepared, verified content for the topics you chose so that it reads \
        naturally for them.

        # Choosing

        - Choose at most \(maximumLessonCount) lessons. Fewer is better than padding. If only one \
        event is worth explaining, return exactly one lesson.
        - Prefer information that is (a) useful the very next time they drive, and (b) likely to be \
        unfamiliar to someone who did not learn to drive in Korea.
        - A driver on their first drive in Korea needs the basics of how something works. A driver \
        who has done this before does not need those repeated.
        - Never choose two topics that would end up saying nearly the same thing.
        - Every lesson must be tied to one of the detected events by its id.

        # Writing

        - Write in \(language).
        - Keep each explanation under 100 words: two to four short sentences.
        - Tone is calm and matter-of-fact. You are a well-informed passenger, not an examiner and \
        not a safety campaign.
        - Begin by referring to what actually happened on this drive, using only the numbers given \
        in that event's facts.
        - Then explain how the rule works, using only the verified facts supplied under that topic.
        - If the topic supplies an action note, finish with what to do next time.

        # Hard limits

        These are not style preferences. Breaking one of them makes the app wrong, not just clumsy.

        - Do NOT state or imply that the driver committed a violation, broke a law, was caught, or \
        owes anything. The app compared GPS speed against a public road dataset. Both carry error, \
        and no enforcement result is known to anyone.
        - Do NOT introduce any Korean traffic law, fine amount, penalty point, demerit, deadline, \
        phone number, or web address that is not present in the supplied topic facts. Your own \
        knowledge of Korean traffic law is not a source here.
        - Do NOT state a monetary amount. No amounts appear in the supplied facts, and that is \
        deliberate.
        - Do NOT alter the numbers in the event facts, and do not add numbers of your own.
        - Do NOT use alarming words such as "dangerous", "illegal", "caught", "penalty", "fined".
        - If the supplied facts are not enough to explain something fully, say less. Never fill the \
        gap from memory.

        # Output

        Return JSON matching the supplied schema.

        - `topicId` must be one of the supplied topic ids.
        - `eventId` must be one of the supplied event ids.
        - `title`: at most six words, sentence case, no trailing period.
        - `explanation`: the text the driver reads.
        - `reason`: one short sentence for the app's developers explaining why you picked this \
        lesson. The driver never sees it.
        - `summary`: one short sentence for the top of the screen. Do NOT count the lessons in it — \
        the screen already displays the count next to them. No exclamation marks.
        """
    }

    // MARK: - 입력

    /// 모델에 넘길 입력 JSON.
    ///
    /// `DriveSample`(GPS 원본)은 여기 없다. `DebriefRequest` 가 애초에 그걸 들고 있지 않아서,
    /// 실수로 넣으려 해도 타입이 막는다.
    static func input(for request: DebriefRequest) throws -> String {
        let payload = InputPayload(request: request)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 지시문을 따로 못 보낼 때 쓰는 합본. (`GeminiConfiguration.sendsSystemInstructionSeparately`)
    static func combinedInput(for request: DebriefRequest) throws -> String {
        let instruction = systemInstruction(language: request.driver.language,
                                            maximumLessonCount: request.maximumLessonCount)
        return """
        \(instruction)

        # This drive

        \(try input(for: request))
        """
    }

    // MARK: - 입력 페이로드

    private struct InputPayload: Encodable {
        var driver: Driver
        var trip: Trip
        var events: [Event]
        var availableTopics: [Topic]
        var maxLessons: Int

        init(request: DebriefRequest) {
            driver = Driver(language: request.driver.language,
                            firstDriveInKorea: request.driver.isFirstDriveInKorea)
            trip = Trip(origin: request.trip.origin,
                        destination: request.trip.destination,
                        distance: request.trip.distanceDescription,
                        duration: request.trip.durationDescription)
            events = request.events.map(Event.init)
            availableTopics = request.availableTopics.map(Topic.init)
            maxLessons = request.maximumLessonCount
        }

        struct Driver: Encodable {
            var language: String
            var firstDriveInKorea: Bool
        }

        struct Trip: Encodable {
            var origin: String?
            var destination: String?
            var distance: String
            var duration: String
        }

        /// 감지된 사건. `facts` 는 전부 코드가 계산했거나 공공데이터에서 온 값이다.
        struct Event: Encodable {
            var id: String
            var type: String
            var whatHappened: String
            var roadName: String?
            var facts: [String: String]
            var relatedTopicIds: [String]

            init(_ event: DriveEvent) {
                id = event.id
                type = event.kind.rawValue
                whatHappened = event.summary
                roadName = event.roadName
                facts = Dictionary(event.facts.map { ($0.key, $0.value) },
                                   uniquingKeysWith: { first, _ in first })
                relatedTopicIds = event.relatedTopicIDs.map(\.rawValue)
            }
        }

        /// 준비된 검증 콘텐츠. **모델이 말할 수 있는 사실의 전부.**
        struct Topic: Encodable {
            var id: String
            var workingTitle: String
            var verifiedFacts: [String]
            var actionNote: String?
            var source: String

            init(_ topic: DebriefTopic) {
                id = topic.id.rawValue
                workingTitle = topic.title
                verifiedFacts = topic.facts
                actionNote = topic.actionNote
                source = topic.source
            }
        }
    }

    // MARK: - 응답 스키마

    /// 이번 요청에 맞춘 JSON 스키마.
    ///
    /// `topicId` / `eventId` 를 실제 값들의 `enum` 으로 좁힌다. 프롬프트로 "지어내지 마라"
    /// 라고 쓰는 것과, 스키마가 애초에 다른 값을 못 만들게 하는 것은 다르다. 둘 다 한다.
    static func responseSchema(for request: DebriefRequest) -> JSONValue {

        let topicIDs = request.availableTopics.map { JSONValue.string($0.id.rawValue) }
        let eventIDs = request.events.map { JSONValue.string($0.id) }

        var lessonProperties: [String: JSONValue] = [
            "topicId": .object([
                "type": .string("string"),
                "description": .string("Which prepared topic this lesson explains."),
                "enum": .array(topicIDs)
            ]),
            "title": .object([
                "type": .string("string"),
                "description": .string("At most six words, sentence case, no trailing period.")
            ]),
            "explanation": .object([
                "type": .string("string"),
                "description": .string(
                    "Under 100 words. Starts from what happened on this drive, then explains the "
                    + "rule using only the verified facts for this topic."
                )
            ]),
            "reason": .object([
                "type": .string("string"),
                "description": .string("One sentence for the developers on why this was chosen. Not shown to the driver.")
            ])
        ]

        var required: [JSONValue] = [
            .string("topicId"), .string("title"), .string("explanation"), .string("reason")
        ]

        // 사건이 하나도 없으면 `enum: []` 이 되어 스키마가 거부당한다.
        // 그 경우 사건 연결 자체를 요구하지 않는다.
        if !eventIDs.isEmpty {
            lessonProperties["eventId"] = .object([
                "type": .string("string"),
                "description": .string("Which detected event this lesson refers to."),
                "enum": .array(eventIDs)
            ])
            required.append(.string("eventId"))
        }

        return .object([
            "type": .string("object"),
            "properties": .object([
                "summary": .object([
                    "type": .string("string"),
                    "description": .string(
                        "One short sentence for the top of the screen. Does not count the lessons."
                    )
                ]),
                "lessons": .object([
                    "type": .string("array"),
                    "minItems": .integer(0),
                    "maxItems": .integer(request.maximumLessonCount),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object(lessonProperties),
                        "required": .array(required)
                    ])
                ])
            ]),
            "required": .array([.string("summary"), .string("lessons")])
        ])
    }
}

//
//  DebriefLLMClient.swift
//  DriveInGyeongbuk
//
//  LLM 에 넘기는 것과 받는 것. 이 파일이 LLM 의 권한 범위를 정의한다.
//
//  넘기는 것 (`DebriefRequest`)
//    · 운전자에 대해 아는 최소한 (언어, 첫 주행 여부)
//    · 주행 요약 (시간, 거리)
//    · **코드가 감지한 사건들** — GPS 원본이 아니다
//    · **준비된 검증 콘텐츠** — LLM 이 참고할 수 있는 사실의 전부
//
//  받는 것 (`DebriefReport`)
//    · 고른 주제 2~3개와 그것을 고른 이유
//    · 각 주제를 이 운전자에게 맞춰 다시 쓴 설명
//
//  ⚠️ `DriveSample` 이 이 파일 어디에도 없다는 점이 중요하다. GPS 원본을 해석해
//     사건을 판단하는 일은 타입 수준에서 LLM 쪽으로 넘어가지 않는다.
//

import Foundation

// MARK: - 요청

nonisolated struct DebriefRequest: Hashable {

    var driver: Driver
    var trip: Trip
    /// 규칙 기반으로 감지된 사건. 순서는 시간순.
    var events: [DriveEvent]
    /// 고를 수 있는 주제와 그 주제의 검증된 문장들.
    var availableTopics: [DebriefTopic]
    /// 최대 몇 개를 고를지.
    ///
    /// 상한이지 목표가 아니다. 고를 만한 사건이 하나뿐이면 카드도 하나다.
    /// 빈 자리를 채우려고 억지로 주제를 끌어오면 그게 곧 "안 겪은 일을 설명하는" 것이 된다.
    var maximumLessonCount: Int = 3

    nonisolated struct Driver: Hashable {
        /// 설명을 쓸 언어.
        var language: String
        /// 한국에서의 첫 주행인지.
        var isFirstDriveInKorea: Bool
    }

    nonisolated struct Trip: Hashable {
        var origin: String?
        var destination: String?
        var distanceDescription: String
        var durationDescription: String
    }
}

// MARK: - 응답

/// LLM 이 돌려주는 것. 그대로 화면의 입력이 된다.
nonisolated struct DebriefReport: Hashable, Codable {

    /// 한 줄 인사 겸 요약. Figma 1번 화면 헤드라인 아래.
    var summary: String
    /// 고른 안내. 앞이 우선순위가 높다.
    var lessons: [Lesson]

    nonisolated struct Lesson: Hashable, Codable, Identifiable {

        /// 이 안내가 근거로 삼은 사건. `DriveEvent.id`. 사건과 무관한 일반 안내면 nil.
        var eventID: String?
        /// 어떤 주제를 골랐는지.
        var topicID: DebriefTopicID
        /// 이 사건에 맞춰 다시 쓴 제목.
        var title: String
        /// 운전자에게 맞춘 설명. 검증된 문장을 벗어나면 안 된다.
        var explanation: String
        /// 왜 이걸 골랐는지. 화면에는 안 나오고 디버깅·검수용이다.
        var reason: String?

        var id: String { "\(topicID.rawValue)|\(eventID ?? "-")" }

        enum CodingKeys: String, CodingKey {
            case eventID = "eventId"
            case topicID = "topicId"
            case title
            case explanation
            case reason
        }
    }
}

// MARK: -

nonisolated enum DebriefLLMError: Error, LocalizedError {
    /// 응답을 스키마대로 못 읽었다.
    case malformedResponse(String)
    /// 고른 주제가 우리가 준 목록에 없다. 환각이므로 버린다.
    case unknownTopic(String)
    /// 키가 없다.
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail):
            return "안내를 만들지 못했습니다. (\(detail))"
        case .unknownTopic(let id):
            return "준비되지 않은 안내 주제를 골랐습니다. (\(id))"
        case .missingCredentials:
            return "안내 생성에 필요한 키가 설정되지 않았습니다."
        }
    }
}

/// 실제 LLM / 목을 갈아 끼우기 위한 추상화.
protocol DebriefLLMClient {
    /// 사건과 준비된 콘텐츠를 받아 안내를 만든다.
    func makeReport(for request: DebriefRequest) async throws -> DebriefReport
}

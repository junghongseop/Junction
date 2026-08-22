//
//  GeminiInteractionsAPI.swift
//  DriveInGyeongbuk
//
//  Google Gemini Interactions API 전송 계층.
//
//  엔드포인트
//    POST https://generativelanguage.googleapis.com/v1beta/interactions
//    헤더: x-goog-api-key, Content-Type, Api-Revision
//
//  Interactions API 는 예전 `:generateContent` 를 대체한 현재 표준이다. 응답이
//  `candidates` 가 아니라 **`steps` 배열**로 오고, 구조화 출력은 `generationConfig` 가
//  아니라 최상위 `response_format` 으로 지정한다. 그래서 예전 예제를 그대로 옮기면 안 된다.
//
//  실측으로 확인해 둔 것 (2026-08, gemini-3.7-flash)
//    · `steps` 에는 `type: "thought"` 스텝이 섞여 오고 그 스텝에는 `content` 가 없다.
//      본문은 `type: "model_output"` 스텝에만 있다.
//    · `generation_config.max_output_tokens` 는 **생각 토큰과 출력 토큰의 합**에 걸린다.
//      모자라면 HTTP 200 · `status: "incomplete"` 로 반쪽 JSON 이 온다. 자세한 건
//      `GeminiConfiguration.maxOutputTokens` 주석 참고.
//    · 생각 강도는 `generation_config.thinking_level` 로 조절한다 (`low`/`medium`/`high`).
//      `thinking_config` · `reasoning_effort` 는 이 API 가 모르는 이름이라 400 이 난다.
//    · `response_format` 의 `type` 은 `text` 여야 한다. `json_schema` · `json_object` 는
//      지원 목록에 없어 400 이다. `type: "text"` + `mime_type` + `schema` 조합에서
//      스키마(enum 포함)가 실제로 강제되는 것을 확인했다.
//
//  구조는 `NaverMapsRequestRunner` · `JunctionServerRequestRunner` 와 같은 모양이다
//  (설정 + 프로토콜로 감싼 HTTP 클라이언트 + 요청 조립 + 도메인 에러).
//
//  ⚠️ 키는 앱 번들에 들어간다. 자세한 사정은 `GeminiDebriefLLMClient` 머리말 참고.
//

import Foundation

// MARK: - 설정

struct GeminiConfiguration {

    /// API 기준 URL.
    var baseURL: URL
    /// 요청 경로.
    var interactionsPath: String
    /// 모델 ID. 안정 버전을 명시적으로 박아 둔다 — `latest` 류는 어느 날 말투가 바뀐다.
    ///
    /// `gemini-2.5-flash` 는 쓸 수 없다. 신규 사용자에게는 막혀 있어서
    /// "no longer available to new users" 400 이 나고, 구글이 응답에서 직접
    /// `gemini-3.6-flash` 로 갈아타라고 지시한다.
    var model: String
    /// API 리비전 고정. 이걸 안 보내면 서버가 스키마를 바꿀 때 조용히 깨진다.
    var apiRevision: String
    /// API 키.
    var apiKey: String
    /// 네트워크 타임아웃(초).
    var timeout: TimeInterval

    /// 응답 길이 상한.
    ///
    /// ⚠️ **이 값은 생각(thought) 토큰과 출력 토큰이 나눠 쓴다.** 안내 3개 + 요약의 본문은
    /// 300 토큰 남짓이지만, 이 모델은 답을 내기 전에 생각에만 700~1500 토큰을 쓴다.
    /// 그래서 "본문에 넉넉한 값"으로 잡으면 생각이 예산을 다 먹고 본문이 중간에 잘린다.
    /// 잘린 응답은 `status: "incomplete"` 로 오고, 반쪽짜리 JSON 이라 파싱에서 실패한다.
    /// 실측 기준 본문 300 + 생각 1500 이라 넉넉히 4배를 잡아 두었다. 줄이지 말 것.
    var maxOutputTokens: Int

    /// 생각(thinking) 강도. `low` · `medium` · `high` 만 받는다 (끄는 값은 없다).
    ///
    /// 이 기능에서 모델이 하는 일은 "고르고 다시 쓰기" 뿐이고 추론할 게 없다.
    /// `low` 로 두면 생각 토큰이 줄어 `maxOutputTokens` 를 덜 먹고 응답도 빨라진다.
    /// `nil` 이면 필드를 보내지 않고 서버 기본값(medium 상당)을 쓴다.
    var thinkingLevel: String?

    /// 지시문을 `system_instruction` 필드로 따로 보낼지.
    ///
    /// 기본값이 `false` 인 이유: Interactions API 공개 문서에 `system_instruction` 의
    /// **값 형식(문자열인지 `{parts:[...]}` 객체인지)이 나와 있지 않다.** 반면 `input` 이
    /// 문자열이라는 것은 문서의 모든 예제로 확인된다. 그래서 지시문을 `input` 앞에 붙여
    /// 보내는, 깨질 수 없는 쪽을 기본으로 두었다.
    ///
    /// 형식을 확인했다면 이 값을 `true` 로 바꾸면 된다. 그때 `systemInstruction` 이
    /// 문자열로 인코딩된다.
    var sendsSystemInstructionSeparately: Bool

    init(apiKey: String = AppConfig.geminiAPIKey,
         baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!,
         interactionsPath: String = "/v1beta/interactions",
         model: String = "gemini-3.6-flash",
         apiRevision: String = "2026-05-20",
         timeout: TimeInterval = 60,
         maxOutputTokens: Int = 8192,
         thinkingLevel: String? = "low",
         sendsSystemInstructionSeparately: Bool = false) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.interactionsPath = interactionsPath
        self.model = model
        self.apiRevision = apiRevision
        self.timeout = timeout
        self.maxOutputTokens = maxOutputTokens
        self.thinkingLevel = thinkingLevel
        self.sendsSystemInstructionSeparately = sendsSystemInstructionSeparately
    }

    static var `default`: GeminiConfiguration { GeminiConfiguration() }

    var hasCredentials: Bool { !apiKey.isEmpty }
}

// MARK: - 에러

enum GeminiError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidRequest(String)
    case transport(String)
    /// 401 / 403 — 키가 틀렸거나 권한이 없다.
    case unauthorized(String)
    /// 429 — 쿼터 초과.
    case rateLimited(String)
    /// 그 밖의 2xx 아닌 응답.
    case httpStatus(code: Int, body: String)
    /// 응답은 왔는데 본문에서 텍스트를 못 찾았다.
    case emptyResponse(String)
    /// 토큰 예산이 떨어져 본문이 중간에 잘렸다. (`status: "incomplete"`)
    ///
    /// `decoding` 과 따로 두는 이유: 원인이 "모델이 스키마를 어겼다" 가 아니라
    /// "`maxOutputTokens` 가 모자랐다" 라서 손볼 곳이 완전히 다르다.
    case truncated(outputTokens: Int?, limit: Int)
    /// 모델이 스키마를 안 지켰다.
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 설정되지 않았습니다. Config.xcconfig 의 Gemini_API_Key 를 확인해 주세요."
        case .invalidRequest(let reason):
            return "요청을 만들지 못했습니다. (\(reason))"
        case .transport(let reason):
            return "Gemini 서버에 연결하지 못했습니다. (\(reason))"
        case .unauthorized(let detail):
            return "Gemini API 키가 거부되었습니다. (\(detail))"
        case .rateLimited(let detail):
            return "Gemini API 호출 한도를 넘었습니다. 잠시 후 다시 시도해 주세요. (\(detail))"
        case .httpStatus(let code, let body):
            return "Gemini 서버가 \(code) 를 반환했습니다. \(body.prefix(300))"
        case .emptyResponse(let detail):
            return "Gemini 응답이 비어 있습니다. (\(detail))"
        case .truncated(let outputTokens, let limit):
            let used = outputTokens.map(String.init) ?? "?"
            return "Gemini 응답이 토큰 한도에서 잘렸습니다. "
                + "(출력 \(used) / 한도 \(limit) — GeminiConfiguration.maxOutputTokens 를 늘려야 합니다)"
        case .decoding(let reason):
            return "Gemini 응답을 해석하지 못했습니다. (\(reason))"
        }
    }
}

// MARK: - 전송 계층

/// 테스트에서 갈아끼울 수 있도록 최소한만 추상화한 HTTP 클라이언트.
protocol GeminiHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionGeminiHTTPClient: GeminiHTTPClient {
    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GeminiError.transport("HTTP 응답이 아닙니다.")
            }
            return (data, http)
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.transport(error.localizedDescription)
        }
    }
}

/// 요청 조립과 실행.
struct GeminiRequestRunner {

    var configuration: GeminiConfiguration
    var httpClient: GeminiHTTPClient

    init(configuration: GeminiConfiguration = .default,
         httpClient: GeminiHTTPClient = URLSessionGeminiHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    func makeRequest(body: GeminiInteractionRequestDTO) throws -> URLRequest {
        guard configuration.hasCredentials else { throw GeminiError.missingAPIKey }

        guard let url = URL(string: configuration.interactionsPath, relativeTo: configuration.baseURL) else {
            throw GeminiError.invalidRequest("URL 조립 실패")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 키는 쿼리(`?key=`)로도 보낼 수 있지만 헤더로 보낸다.
        // 쿼리에 넣으면 URL 이 로그·프록시·크래시 리포트에 그대로 남는다.
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue(configuration.apiRevision, forHTTPHeaderField: "Api-Revision")

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw GeminiError.invalidRequest("본문 인코딩 실패: \(error.localizedDescription)")
        }
        return request
    }

    func send(_ request: URLRequest) async throws -> GeminiInteractionResponseDTO {
        let (data, http) = try await httpClient.data(for: request)

        guard (200..<300).contains(http.statusCode) else {
            throw Self.makeError(statusCode: http.statusCode, data: data)
        }

        do {
            return try JSONDecoder().decode(GeminiInteractionResponseDTO.self, from: data)
        } catch {
            throw GeminiError.decoding(error.localizedDescription)
        }
    }

    private static func makeError(statusCode: Int, data: Data) -> GeminiError {
        let body = String(data: data, encoding: .utf8) ?? ""
        let detail = (try? JSONDecoder().decode(GeminiErrorEnvelopeDTO.self, from: data))?.error?.message
            ?? body.prefix(300).description

        switch statusCode {
        case 400: return .invalidRequest(detail)
        case 401, 403: return .unauthorized(detail)
        case 429: return .rateLimited(detail)
        default: return .httpStatus(code: statusCode, body: body)
        }
    }
}

// MARK: - 요청 DTO

struct GeminiInteractionRequestDTO: Encodable {

    var model: String
    /// 사용자 입력. 이 API 에서는 문자열 하나로 보낼 수 있다.
    var input: String
    /// 시스템 지시문. `GeminiConfiguration.sendsSystemInstructionSeparately` 가 켜졌을 때만 채운다.
    var systemInstruction: String?
    var responseFormat: ResponseFormatDTO?
    var generationConfig: GenerationConfigDTO?
    /// 서버에 대화를 저장하지 않는다. 주행 기록이 남는 걸 원치 않고, 이어 붙일 대화도 없다.
    var store: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case systemInstruction = "system_instruction"
        case responseFormat = "response_format"
        case generationConfig = "generation_config"
        case store
    }

    /// 구조화 출력 지정. 예전 API 의 `generationConfig.responseSchema` 자리다.
    struct ResponseFormatDTO: Encodable {
        var type = "text"
        var mimeType = "application/json"
        var schema: JSONValue

        enum CodingKeys: String, CodingKey {
            case type
            case mimeType = "mime_type"
            case schema
        }
    }

    struct GenerationConfigDTO: Encodable {
        var maxOutputTokens: Int?
        /// `low` · `medium` · `high`. nil 이면 필드를 보내지 않는다.
        var thinkingLevel: String?

        enum CodingKeys: String, CodingKey {
            case maxOutputTokens = "max_output_tokens"
            case thinkingLevel = "thinking_level"
        }
    }
}

// MARK: - 응답 DTO

/// Interactions API 응답.
///
/// 생성된 텍스트는 `steps[].content[].text` 에 있다. 예전 API 의
/// `candidates[0].content.parts[0].text` 와 위치가 다르다.
struct GeminiInteractionResponseDTO: Decodable {

    var id: String?
    var status: String?
    var steps: [StepDTO]?
    var errors: [ErrorDTO]?
    var usage: UsageDTO?

    struct StepDTO: Decodable {
        /// `model_output`, `tool_call` 등.
        var type: String?
        var status: String?
        var content: [ContentDTO]?
    }

    struct ContentDTO: Decodable {
        /// `text` 등.
        var type: String?
        var text: String?
    }

    struct ErrorDTO: Decodable {
        var code: String?
        var message: String?
    }

    struct UsageDTO: Decodable {
        var totalInputTokens: Int?
        var totalOutputTokens: Int?
        var totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case totalTokens = "total_tokens"
        }
    }

    /// 모델이 낸 텍스트. 여러 조각이면 이어 붙인다.
    ///
    /// `model_output` 스텝을 먼저 찾고, 못 찾으면 스텝 종류를 가리지 않고 텍스트를 긁는다.
    /// (스텝 타입 이름이 늘어나도 조용히 빈 응답이 되지 않도록)
    var outputText: String? {
        let steps = steps ?? []

        let preferred = steps.filter { $0.type == "model_output" }
        let source = preferred.isEmpty ? steps : preferred

        // 한 줄로 이어 쓰면 타입 검사기가 시간 안에 못 푼다. 단계마다 타입을 박아 둔다.
        let contents: [ContentDTO] = source.flatMap { $0.content ?? [] }
        let textual: [ContentDTO] = contents.filter { $0.type == nil || $0.type == "text" }
        let pieces: [String] = textual.compactMap { $0.text }
        let text: String = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)

        return text.isEmpty ? nil : text
    }

    /// 본문이 토큰 한도에서 잘렸는지.
    ///
    /// 잘린 응답도 HTTP 200 으로 오고 `steps` 도 정상 모양이다. 다른 점은 `status` 가
    /// `completed` 가 아니라 `incomplete` 인 것뿐이라, 이걸 안 보면 "JSON 파싱 실패"
    /// 로만 보여서 원인을 엉뚱한 데서 찾게 된다.
    var isIncomplete: Bool { status == "incomplete" }

    /// 응답에 실려 온 실패 사유.
    var errorMessage: String? {
        guard let errors, !errors.isEmpty else { return nil }
        return errors.compactMap { [$0.code, $0.message].compactMap { $0 }.joined(separator: ": ") }
            .joined(separator: " / ")
    }
}

/// HTTP 실패 응답 본문. Google API 공통 형식이다.
struct GeminiErrorEnvelopeDTO: Decodable {
    var error: ErrorBody?

    struct ErrorBody: Decodable {
        var code: Int?
        var message: String?
        var status: String?
    }
}

// MARK: - JSON 스키마 표현

/// 임의의 JSON 값. `response_format.schema` 를 조립하는 데만 쓴다.
///
/// 스키마는 요청마다 달라진다 — 사건 ID 와 주제 ID 를 `enum` 으로 박아 넣기 때문이다.
/// 고정 구조체로는 표현할 수 없어서 값 트리를 직접 만든다.
nonisolated indirect enum JSONValue: Encodable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
        case .null: try container.encodeNil()
        }
    }
}

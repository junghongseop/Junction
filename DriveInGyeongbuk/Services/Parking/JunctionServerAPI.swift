//
//  JunctionServerAPI.swift
//  DriveInGyeongbuk
//
//  주차장 · 주정차 금지구역 백엔드(Junction Server) 공용 전송 계층.
//
//  데이터 출처
//    https://junction-server.onrender.com  (스펙: /docs, /openapi.json)
//    - GET /api/v1/parking-lots           : 목적지 반경 2km 주차장
//    - GET /api/v1/parking-restrictions   : 목적지 반경 2km 주정차 금지구역
//    - GET /health                        : 서버 상태
//
//  이 서버는 요청마다 원본 공공데이터를 읽어 네이버 Geocoding/Directions 로
//  실제 도로 경로를 만들어 준다. 즉 앱에는 키가 필요 없지만, 서버 쪽 응답이 느릴 수 있다.
//  (무료 호스팅이라 첫 요청에서 콜드 스타트로 수십 초가 걸리기도 한다 → 타임아웃을 넉넉히 잡았다)
//
//  `Services/Parking` 과 `Services/Enforcement` 가 같은 서버를 쓰므로
//  전송 계층은 여기 한 곳에만 둔다. 구조는 `NaverMapsRequestRunner` 와 같은 모양이다.
//

import Foundation

// MARK: - 설정

struct JunctionServerConfiguration {

    /// 백엔드 기준 URL.
    var baseURL: URL

    var parkingLotsPath: String
    var parkingRestrictionsPath: String
    var healthPath: String

    /// 네트워크 타임아웃(초).
    var timeout: TimeInterval

    /// 서버가 강제하는 검색 반경(m). 쿼리로 바꿀 수 없다.
    /// 더 좁게 보고 싶으면 응답을 받은 뒤 앱에서 잘라낸다.
    static let fixedSearchRadiusMeters = 2000

    init(baseURL: URL = URL(string: "https://junction-server.onrender.com")!,
         parkingLotsPath: String = "/api/v1/parking-lots",
         parkingRestrictionsPath: String = "/api/v1/parking-restrictions",
         healthPath: String = "/health",
         timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.parkingLotsPath = parkingLotsPath
        self.parkingRestrictionsPath = parkingRestrictionsPath
        self.healthPath = healthPath
        self.timeout = timeout
    }

    static var `default`: JunctionServerConfiguration { JunctionServerConfiguration() }
}

// MARK: - 에러

enum JunctionServerError: Error, LocalizedError, Equatable {
    /// 요청을 만들 수 없음 (좌표 범위 초과, URL 조립 실패 등).
    case invalidRequest(String)
    /// 네트워크 실패.
    case transport(String)
    /// 400 — 목적지가 경상북도 밖이거나 행정구역을 확인할 수 없음.
    case outsideCoverage(String)
    /// 502 — 서버가 네이버 Maps API 를 호출하는 데 실패.
    case upstreamFailure(String)
    /// 503 — 서버의 원본 데이터/인증정보가 준비되지 않음.
    case serviceUnavailable(String)
    /// 그 밖의 2xx 아닌 응답.
    case httpStatus(code: Int, body: String)
    /// JSON 디코딩 실패.
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let reason):
            return "잘못된 요청입니다. (\(reason))"
        case .transport(let reason):
            return "주차 정보 서버에 연결하지 못했습니다. (\(reason))"
        case .outsideCoverage(let detail):
            return "경상북도 안의 목적지만 조회할 수 있습니다. (\(detail))"
        case .upstreamFailure(let detail):
            return "서버가 지도 API 를 호출하지 못했습니다. 잠시 후 다시 시도해 주세요. (\(detail))"
        case .serviceUnavailable(let detail):
            return "주차 정보 서버가 준비되지 않았습니다. (\(detail))"
        case .httpStatus(let code, let body):
            return "주차 정보 서버가 \(code) 를 반환했습니다. \(body.prefix(300))"
        case .decoding(let reason):
            return "서버 응답을 해석하지 못했습니다. (\(reason))"
        }
    }
}

// MARK: - 전송 계층

/// 테스트에서 갈아끼울 수 있도록 최소한만 추상화한 HTTP 클라이언트.
protocol JunctionServerHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionJunctionServerHTTPClient: JunctionServerHTTPClient {
    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JunctionServerError.transport("HTTP 응답이 아닙니다.")
            }
            return (data, http)
        } catch let error as JunctionServerError {
            throw error
        } catch {
            throw JunctionServerError.transport(error.localizedDescription)
        }
    }
}

/// 두 API 클라이언트가 공유하는 요청 조립 / 실행 로직.
struct JunctionServerRequestRunner {

    var configuration: JunctionServerConfiguration
    var httpClient: JunctionServerHTTPClient

    init(configuration: JunctionServerConfiguration = .default,
         httpClient: JunctionServerHTTPClient = URLSessionJunctionServerHTTPClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    /// 목적지 좌표를 쿼리 파라미터로 만든다.
    ///
    /// 네이버 REST 와 달리 이 서버는 `latitude` / `longitude` 를 따로 받는다.
    /// (`NaverCoordinate.apiQueryValue` 의 `경도,위도` 형식이 아니다)
    func makeDestinationRequest(path: String, coordinate: NaverCoordinate) throws -> URLRequest {
        guard (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else {
            throw JunctionServerError.invalidRequest("좌표 범위를 벗어났습니다. \(coordinate.apiQueryValue)")
        }

        return try makeRequest(path: path, queryItems: [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude))
        ])
    }

    func makeRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw JunctionServerError.invalidRequest("URL 조립 실패: \(configuration.baseURL)\(path)")
        }
        components.path = components.path + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw JunctionServerError.invalidRequest("쿼리 인코딩 실패")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// 요청을 실행하고 JSON 을 디코딩한다.
    /// 실패 응답(`{"detail": "..."}`)은 상태 코드에 맞는 도메인 에러로 바꾼다.
    func send<Response: Decodable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let (data, http) = try await httpClient.data(for: request)

        guard (200..<300).contains(http.statusCode) else {
            throw Self.makeError(statusCode: http.statusCode, data: data)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw JunctionServerError.decoding(error.localizedDescription)
        }
    }

    // MARK: 내부

    private static func makeError(statusCode: Int, data: Data) -> JunctionServerError {
        let body = String(data: data, encoding: .utf8) ?? ""
        // FastAPI 의 실패 응답은 `detail` 하나만 담고 있다.
        // 422 는 `detail` 이 배열이라 디코딩이 실패할 수 있어 원문을 그대로 넘긴다.
        let detail = (try? JSONDecoder().decode(JunctionServerErrorDTO.self, from: data))?.detail
            ?? body.prefix(300).description

        switch statusCode {
        case 400: return .outsideCoverage(detail)
        case 422: return .invalidRequest(detail)
        case 502: return .upstreamFailure(detail)
        case 503: return .serviceUnavailable(detail)
        default:  return .httpStatus(code: statusCode, body: body)
        }
    }
}

// MARK: - 공용 DTO

/// 실패 응답 본문.
struct JunctionServerErrorDTO: Decodable {
    var detail: String
}

/// `GET /health` 응답.
struct JunctionServerHealthDTO: Decodable {
    /// 정상이면 `"ok"`.
    var status: String
}

/// 응답의 좌표 객체. 키 이름이 `NaverCoordinate` 와 같아 그대로 디코딩된다.
/// (네이버 REST 와 달리 `[경도, 위도]` 배열이 아니라 `{latitude, longitude}` 객체다)
typealias JunctionServerCoordinateDTO = NaverCoordinate

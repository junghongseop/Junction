//
//  NaverMapDTO.swift
//  DriveInGyeongbuk
//
//  NAVER Cloud Platform Maps API 의 요청/응답 모델과, 두 서비스
//  (NaverGeocodingService / NaverDirectionsService) 가 공유하는 전송 계층을 담는다.
//
//  구성
//  1. Configuration  : 호스트 / 인증 헤더 / 자격 증명
//  2. Error          : 서비스 공통 에러
//  3. Transport      : URLSession 기반 HTTP 클라이언트
//  4. Raw DTO        : 네이버 응답 JSON 을 그대로 옮긴 타입 (`...DTO` 접미사)
//  5. Domain Model   : 앱에서 실제로 쓰는 정제된 모델
//

import Foundation
import CoreLocation

// MARK: - 좌표

/// 위/경도 좌표.
///
/// 네이버 Maps API 는 좌표를 항상 `경도,위도`(x,y) 순서로 주고받는다.
/// 실수를 막기 위해 문자열 변환은 `apiQueryValue` 로만 하도록 한다.
struct NaverCoordinate: Codable, Hashable, Identifiable {
    var latitude: Double
    var longitude: Double

    var id: String { apiQueryValue }

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ clLocationCoordinate: CLLocationCoordinate2D) {
        self.init(latitude: clLocationCoordinate.latitude,
                  longitude: clLocationCoordinate.longitude)
    }

    /// 네이버 API 쿼리 파라미터 표기 (`경도,위도`).
    var apiQueryValue: String { "\(longitude),\(latitude)" }

    /// `경도,위도` 문자열 파싱.
    init?(apiQueryValue: String) {
        let parts = apiQueryValue.split(separator: ",")
        guard parts.count == 2,
              let lng = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lat = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        self.init(latitude: lat, longitude: lng)
    }

    /// 네이버 응답의 `[경도, 위도]` 배열에서 생성.
    init?(xyPair: [Double]) {
        guard xyPair.count >= 2 else { return nil }
        self.init(latitude: xyPair[1], longitude: xyPair[0])
    }

    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// 두 좌표 사이의 대권 거리(m).
    func distance(to other: NaverCoordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// 남서/북동 좌표로 표현한 사각 영역.
struct NaverCoordinateBounds: Codable, Hashable {
    var southWest: NaverCoordinate
    var northEast: NaverCoordinate

    /// 네이버 `bbox` (`[[minX, minY], [maxX, maxY]]`) 에서 생성.
    init?(bbox: [[Double]]) {
        guard bbox.count >= 2,
              let sw = NaverCoordinate(xyPair: bbox[0]),
              let ne = NaverCoordinate(xyPair: bbox[1])
        else { return nil }
        self.southWest = sw
        self.northEast = ne
    }

    init(southWest: NaverCoordinate, northEast: NaverCoordinate) {
        self.southWest = southWest
        self.northEast = northEast
    }
}

// MARK: - 설정

/// 네이버 Maps API 호출에 필요한 호스트/자격 증명 묶음.
///
/// 키는 `Config/Config.xcconfig` → `Info.plist` → `AppConfig` 를 거쳐 주입된다.
/// (`Config.xcconfig` 는 `.gitignore` 대상이므로 로컬에서 직접 만들어야 한다.
///  `Config/Config.xcconfig.sample` 참고)
struct NaverMapsConfiguration {

    /// NCP 애플리케이션의 Client ID (API Key ID).
    var clientID: String
    /// NCP 애플리케이션의 Client Secret (API Key).
    var clientSecret: String

    /// Geocoding / Reverse Geocoding 호스트.
    var geocodingHost: URL
    /// Directions 호스트.
    var directionsHost: URL

    var geocodePath: String
    var reverseGeocodePath: String
    /// Directions 5 는 `/map-direction/v1/driving`,
    /// Directions 15 는 `/map-direction-15/v1/driving`.
    var directionsPath: String

    /// 인증 헤더 필드명. 구형 키를 쓰는 계정이면 이 값만 바꿔주면 된다.
    var clientIDHeaderField: String
    var clientSecretHeaderField: String

    /// 네트워크 타임아웃(초).
    var timeout: TimeInterval

    init(
        clientID: String,
        clientSecret: String,
        geocodingHost: URL = URL(string: "https://maps.apigw.ntruss.com")!,
        directionsHost: URL = URL(string: "https://maps.apigw.ntruss.com")!,
        geocodePath: String = "/map-geocode/v2/geocode",
        reverseGeocodePath: String = "/map-reversegeocode/v2/gc",
        directionsPath: String = "/map-direction/v1/driving",
        clientIDHeaderField: String = "x-ncp-apigw-api-key-id",
        clientSecretHeaderField: String = "x-ncp-apigw-api-key",
        timeout: TimeInterval = 15
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.geocodingHost = geocodingHost
        self.directionsHost = directionsHost
        self.geocodePath = geocodePath
        self.reverseGeocodePath = reverseGeocodePath
        self.directionsPath = directionsPath
        self.clientIDHeaderField = clientIDHeaderField
        self.clientSecretHeaderField = clientSecretHeaderField
        self.timeout = timeout
    }

    /// `AppConfig` 에서 읽어온 기본 설정.
    static var `default`: NaverMapsConfiguration {
        NaverMapsConfiguration(clientID: AppConfig.naverMapClientID,
                               clientSecret: AppConfig.naverMapClientSecret)
    }

    /// REST API 호출에 필요한 키가 모두 채워져 있는지.
    var hasCredentials: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    var authorizationHeaders: [String: String] {
        [
            clientIDHeaderField: clientID,
            clientSecretHeaderField: clientSecret,
            "Accept": "application/json"
        ]
    }
}

// MARK: - 에러

enum NaverMapsError: Error, LocalizedError, Equatable {
    /// Client ID / Secret 이 비어 있음.
    case missingCredentials
    /// 요청을 만들 수 없음 (빈 검색어, URL 조립 실패 등).
    case invalidRequest(String)
    /// 네트워크 실패.
    case transport(String)
    /// 2xx 가 아닌 응답.
    case httpStatus(code: Int, body: String)
    /// JSON 디코딩 실패.
    case decoding(String)
    /// HTTP 는 성공했지만 API 가 실패를 반환.
    case api(code: String, message: String)
    /// 결과가 비어 있음.
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "네이버 지도 API 키가 설정되지 않았습니다. Config/Config.xcconfig 를 확인해 주세요."
        case .invalidRequest(let reason):
            return "잘못된 요청입니다. (\(reason))"
        case .transport(let reason):
            return "네트워크 오류가 발생했습니다. (\(reason))"
        case .httpStatus(let code, let body):
            let trimmed = body.prefix(300)
            return "서버가 \(code) 를 반환했습니다. \(trimmed)"
        case .decoding(let reason):
            return "응답을 해석하지 못했습니다. (\(reason))"
        case .api(let code, let message):
            return "네이버 API 오류 [\(code)] \(message)"
        case .emptyResult:
            return "결과가 없습니다."
        }
    }
}

// MARK: - 전송 계층

/// 테스트에서 갈아끼울 수 있도록 최소한만 추상화한 HTTP 클라이언트.
protocol NaverMapsHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionNaverMapsHTTPClient: NaverMapsHTTPClient {
    var session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NaverMapsError.transport("HTTP 응답이 아닙니다.")
            }
            return (data, http)
        } catch let error as NaverMapsError {
            throw error
        } catch {
            throw NaverMapsError.transport(error.localizedDescription)
        }
    }
}

/// 두 서비스가 공유하는 요청 조립 / 실행 로직.
struct NaverMapsRequestRunner {
    var configuration: NaverMapsConfiguration
    var httpClient: NaverMapsHTTPClient

    init(configuration: NaverMapsConfiguration, httpClient: NaverMapsHTTPClient) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    /// 인증 헤더가 붙은 GET 요청을 만든다.
    func makeRequest(host: URL, path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard configuration.hasCredentials else { throw NaverMapsError.missingCredentials }

        // `appendingPathComponent` 는 "/" 로 시작하는 경로를 붙이면 슬래시가 겹치므로
        // URLComponents 에 직접 경로를 지정한다.
        guard var components = URLComponents(url: host, resolvingAgainstBaseURL: false) else {
            throw NaverMapsError.invalidRequest("URL 조립 실패: \(host)\(path)")
        }
        components.path = components.path + path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw NaverMapsError.invalidRequest("쿼리 인코딩 실패")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.timeout)
        request.httpMethod = "GET"
        for (field, value) in configuration.authorizationHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    /// 요청을 실행하고 JSON 을 디코딩한다.
    func send<Response: Decodable>(_ request: URLRequest, as type: Response.Type) async throws -> Response {
        let (data, http) = try await httpClient.data(for: request)

        guard (200..<300).contains(http.statusCode) else {
            throw NaverMapsError.httpStatus(code: http.statusCode,
                                            body: String(data: data, encoding: .utf8) ?? "")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NaverMapsError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Geocoding DTO

/// `GET /map-geocode/v2/geocode` 응답.
struct NaverGeocodeResponseDTO: Decodable {
    var status: String
    var errorMessage: String?
    var meta: MetaDTO?
    var addresses: [AddressDTO]?

    struct MetaDTO: Decodable {
        var totalCount: Int?
        var page: Int?
        var count: Int?
    }

    struct AddressDTO: Decodable {
        var roadAddress: String?
        var jibunAddress: String?
        var englishAddress: String?
        /// 경도(문자열).
        var x: String?
        /// 위도(문자열).
        var y: String?
        var distance: Double?
        var addressElements: [AddressElementDTO]?
    }

    struct AddressElementDTO: Decodable {
        var types: [String]?
        var longName: String?
        var shortName: String?
        var code: String?
    }
}

/// `GET /map-reversegeocode/v2/gc` 응답.
struct NaverReverseGeocodeResponseDTO: Decodable {
    var status: StatusDTO
    var results: [ResultDTO]?

    struct StatusDTO: Decodable {
        var code: Int
        var name: String
        var message: String
    }

    struct ResultDTO: Decodable {
        /// `legalcode` / `admcode` / `addr` / `roadaddr`
        var name: String
        var region: RegionDTO?
        var land: LandDTO?
    }

    struct RegionDTO: Decodable {
        var area0: AreaDTO?
        var area1: AreaDTO?
        var area2: AreaDTO?
        var area3: AreaDTO?
        var area4: AreaDTO?
    }

    struct AreaDTO: Decodable {
        var name: String?
    }

    struct LandDTO: Decodable {
        var type: String?
        var number1: String?
        var number2: String?
        var name: String?
        var addition0: AdditionDTO?

        struct AdditionDTO: Decodable {
            var type: String?
            var value: String?
        }
    }
}

// MARK: - Directions DTO

/// `GET /map-direction/v1/driving` 응답.
struct NaverDirectionsResponseDTO: Decodable {
    var code: Int
    var message: String?
    var currentDateTime: String?
    /// 탐색 옵션 이름(`traoptimal` 등)이 키인 딕셔너리.
    var route: [String: [RouteDTO]]?

    struct RouteDTO: Decodable {
        var summary: SummaryDTO
        /// `[[경도, 위도], ...]`
        var path: [[Double]]?
        var section: [SectionDTO]?
        var guide: [GuideDTO]?
    }

    struct SummaryDTO: Decodable {
        var start: PointDTO?
        var goal: GoalPointDTO?
        var distance: Int?
        /// 밀리초.
        var duration: Int?
        var departureTime: String?
        var bbox: [[Double]]?
        var tollFare: Int?
        var taxiFare: Int?
        var fuelPrice: Int?
    }

    struct PointDTO: Decodable {
        var location: [Double]?
    }

    struct GoalPointDTO: Decodable {
        var location: [Double]?
        var dir: Int?
    }

    struct SectionDTO: Decodable {
        var pointIndex: Int?
        var pointCount: Int?
        var distance: Int?
        var name: String?
        /// 0: 정보 없음, 1: 원활 … 4: 정체
        var congestion: Int?
        /// 해당 구간의 현재 통행 속도(km/h). 제한속도가 아님에 유의.
        var speed: Int?
    }

    struct GuideDTO: Decodable {
        var pointIndex: Int?
        /// 네이버 안내 코드. 문서 개정이 잦아 원본 값을 그대로 보존한다.
        var type: Int?
        var instructions: String?
        var distance: Int?
        /// 밀리초.
        var duration: Int?
    }
}

// MARK: - Domain Model (Geocoding)

/// 주소 검색 결과 한 건.
struct GeocodedPlace: Identifiable, Hashable {
    var id: String { "\(roadAddress)|\(jibunAddress)|\(coordinate.apiQueryValue)" }

    var coordinate: NaverCoordinate
    var roadAddress: String
    var jibunAddress: String
    /// 외국인 사용자에게 보여줄 영문 주소.
    var englishAddress: String
    /// 시/도 (예: 경상북도)
    var sido: String?
    /// 시/군/구 (예: 경주시)
    var sigungu: String?
    /// 건물명 등 참고 이름.
    var placeName: String?

    /// 화면에 보여줄 대표 주소 (도로명 우선).
    var displayAddress: String {
        roadAddress.isEmpty ? jibunAddress : roadAddress
    }

    /// 경상북도 내부인지 여부. (경북 특화 안내 on/off 판단용)
    var isInGyeongbuk: Bool {
        guard let sido else { return false }
        return sido.contains("경상북도") || sido.contains("경북")
    }
}

/// 좌표 → 주소 변환 결과.
struct ReverseGeocodedAddress: Hashable {
    var coordinate: NaverCoordinate
    var roadAddress: String?
    var jibunAddress: String?
    var sido: String?
    var sigungu: String?
    var eupmyeondong: String?
    var buildingName: String?

    var displayAddress: String {
        roadAddress ?? jibunAddress ?? [sido, sigungu, eupmyeondong]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var isInGyeongbuk: Bool {
        guard let sido else { return false }
        return sido.contains("경상북도") || sido.contains("경북")
    }
}

// MARK: - Domain Model (Directions)

/// Directions 5 탐색 옵션.
enum RouteOption: String, CaseIterable, Identifiable {
    /// 실시간 빠른 길
    case fastest = "trafast"
    /// 편한 길
    case comfortable = "tracomfort"
    /// 최적 경로
    case optimal = "traoptimal"
    /// 무료 우선 (톨게이트 회피)
    case avoidToll = "traavoidtoll"
    /// 자동차 전용도로 회피
    case avoidCarOnly = "traavoidcaronly"

    var id: String { rawValue }

    var koreanTitle: String {
        switch self {
        case .fastest: return "실시간 빠른 길"
        case .comfortable: return "편한 길"
        case .optimal: return "최적 경로"
        case .avoidToll: return "무료 우선"
        case .avoidCarOnly: return "자동차전용도로 회피"
        }
    }

    var englishTitle: String {
        switch self {
        case .fastest: return "Fastest"
        case .comfortable: return "Comfortable"
        case .optimal: return "Optimal"
        case .avoidToll: return "Avoid tolls"
        case .avoidCarOnly: return "Avoid motorways"
        }
    }
}

/// 안내 지점의 성격.
///
/// 네이버가 내려주는 `type` 코드는 공개 문서 개정이 잦아 값만으로 단정하기 어렵다.
/// 그래서 원본 코드(`rawType`)는 그대로 보존하고, 분류는 안내 문구(`instructions`)의
/// 한국어 키워드로 판정한다. 하위 서비스(TollGate/RoadSign)에서 이 값을 쓴다.
enum RouteGuideKind: String, Hashable {
    case departure
    case destination
    case straight
    case turnLeft
    case turnRight
    case uTurn
    case keepLeft
    case keepRight
    case tollGate
    case highwayEntrance
    case highwayExit
    case junction
    case restArea
    case roundabout
    case other

    /// 안내 문구에서 성격을 추론한다.
    static func classify(instructions: String) -> RouteGuideKind {
        let text = instructions.replacingOccurrences(of: " ", with: "")

        func has(_ keywords: [String]) -> Bool {
            keywords.contains { text.contains($0) }
        }

        if has(["출발"]) { return .departure }
        if has(["목적지", "도착"]) { return .destination }
        if has(["요금소", "톨게이트", "하이패스", "TG"]) { return .tollGate }
        if has(["휴게소", "졸음쉼터"]) { return .restArea }
        if has(["분기점", "JC", "분기"]) { return .junction }
        if has(["나들목", "IC진입", "고속도로진입", "진입로"]) { return .highwayEntrance }
        if has(["고속도로출구", "출구", "빠져나", "IC방면"]) { return .highwayExit }
        if has(["회전교차로", "로터리"]) { return .roundabout }
        if has(["유턴", "U턴"]) { return .uTurn }
        if has(["좌회전"]) { return .turnLeft }
        if has(["우회전"]) { return .turnRight }
        if has(["왼쪽"]) { return .keepLeft }
        if has(["오른쪽"]) { return .keepRight }
        if has(["직진"]) { return .straight }
        return .other
    }

    /// UI 에서 쓸 SF Symbol 이름.
    var symbolName: String {
        switch self {
        case .departure: return "flag.circle"
        case .destination: return "flag.checkered"
        case .straight: return "arrow.up"
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.down"
        case .keepLeft: return "arrow.up.left"
        case .keepRight: return "arrow.up.right"
        case .tollGate: return "creditcard"
        case .highwayEntrance: return "arrow.up.right.circle"
        case .highwayExit: return "arrow.down.right.circle"
        case .junction: return "arrow.triangle.branch"
        case .restArea: return "cup.and.saucer"
        case .roundabout: return "arrow.clockwise.circle"
        case .other: return "arrow.up"
        }
    }
}

/// 턴바이턴 안내 한 스텝.
struct RouteStep: Identifiable, Hashable {
    var id = UUID()

    /// `DrivingRoute.path` 상의 인덱스.
    var pointIndex: Int
    /// 해당 안내 지점의 좌표.
    var coordinate: NaverCoordinate
    /// 이 안내 지점부터 다음 안내 지점까지의 거리(m).
    var distance: Int
    /// 이 안내 지점부터 다음 안내 지점까지의 소요 시간(초).
    var duration: Int
    /// 네이버가 내려주는 한국어 안내 문구 (원문 보존).
    var instructions: String
    /// 네이버 원본 안내 코드.
    var rawType: Int
    var kind: RouteGuideKind
    /// 출발지에서 이 지점까지의 누적 거리(m).
    var distanceFromStart: Int
}

/// 경로 구간(도로 단위) 정보.
struct RouteSection: Identifiable, Hashable {
    var id = UUID()

    var pointIndex: Int
    var pointCount: Int
    var distance: Int
    /// 도로명 (예: 경부고속도로)
    var name: String
    /// 0: 정보없음, 1: 원활, 2: 서행, 3: 지체, 4: 정체
    var congestion: Int
    /// 현재 통행 속도(km/h). **제한속도가 아니다.**
    /// 제한속도는 `Services/SpeedLimit` 에서 별도로 채운다.
    var currentSpeed: Int

    var congestionDescription: String {
        switch congestion {
        case 1: return "원활"
        case 2: return "서행"
        case 3: return "지체"
        case 4: return "정체"
        default: return "정보 없음"
        }
    }
}

/// 탐색된 자동차 경로.
struct DrivingRoute: Identifiable, Hashable {
    var id = UUID()

    var option: RouteOption
    var start: NaverCoordinate
    var goal: NaverCoordinate
    /// 경로 폴리라인.
    var path: [NaverCoordinate]
    var sections: [RouteSection]
    var steps: [RouteStep]
    var bounds: NaverCoordinateBounds?

    /// 총 거리(m).
    var distance: Int
    /// 총 소요 시간(초).
    var duration: Int
    /// 통행료(원).
    var tollFare: Int
    /// 택시 요금(원).
    var taxiFare: Int
    /// 유류비(원).
    var fuelPrice: Int

    /// 톨게이트 안내만 추린 것. `TollGateService` 의 입력으로 쓴다.
    var tollGateSteps: [RouteStep] {
        steps.filter { $0.kind == .tollGate }
    }

    /// 사람이 읽는 거리 표기.
    var distanceDescription: String {
        distance >= 1000
            ? String(format: "%.1f km", Double(distance) / 1000)
            : "\(distance) m"
    }

    /// 사람이 읽는 소요 시간 표기.
    var durationDescription: String {
        let minutes = max(0, duration) / 60
        if minutes >= 60 {
            return "\(minutes / 60)시간 \(minutes % 60)분"
        }
        return "\(minutes)분"
    }

    /// 주어진 좌표에서 가장 가까운 경로 점의 인덱스.
    /// 주행 중 현재 위치를 경로에 스냅할 때 쓴다.
    func nearestPathIndex(to coordinate: NaverCoordinate) -> Int? {
        guard !path.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in path.enumerated() {
            let d = point.distance(to: coordinate)
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// 현재 위치 기준으로 아직 지나지 않은 다음 안내 스텝.
    func nextStep(from coordinate: NaverCoordinate) -> RouteStep? {
        guard let index = nearestPathIndex(to: coordinate) else { return nil }
        return steps.first { $0.pointIndex > index }
    }

    /// 현재 위치가 속한 구간.
    func section(at coordinate: NaverCoordinate) -> RouteSection? {
        guard let index = nearestPathIndex(to: coordinate) else { return nil }
        return sections.last { $0.pointIndex <= index }
    }
}

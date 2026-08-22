//
//  NaverLocationSearchService.swift
//  DriveInGyeongbuk
//
//  NAVER API HUB 지역 검색 API를 이용한 업체/기관명 검색.
//  NCP Maps API와 서비스 및 인증 키가 다르므로 별도 서비스로 둔다.
//

import Foundation

protocol NaverLocationSearchServicing {
    func search(query: String, display: Int) async throws -> [NaverLocation]
}

extension NaverLocationSearchServicing {
    func search(query: String) async throws -> [NaverLocation] {
        try await search(query: query, display: 5)
    }
}

struct NaverLocation: Identifiable, Hashable {
    var id: String { "\(title)|\(coordinate.apiQueryValue)" }
    var title: String
    var category: String
    var description: String
    var roadAddress: String
    var jibunAddress: String
    var coordinate: NaverCoordinate
    var link: URL?

    var displayAddress: String { roadAddress.isEmpty ? jibunAddress : roadAddress }

    var geocodedPlace: GeocodedPlace {
        GeocodedPlace(coordinate: coordinate,
                      roadAddress: roadAddress,
                      jibunAddress: jibunAddress,
                      englishAddress: "",
                      sido: Self.firstAddressComponent(of: displayAddress),
                      sigungu: Self.secondAddressComponent(of: displayAddress),
                      placeName: title)
    }

    private static func firstAddressComponent(of address: String) -> String? {
        address.split(separator: " ").first.map(String.init)
    }

    private static func secondAddressComponent(of address: String) -> String? {
        let parts = address.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : nil
    }
}

enum NaverLocationSearchError: Error, LocalizedError, Equatable {
    case missingCredentials
    case invalidQuery
    case invalidResponse
    case transport(String)
    case httpStatus(code: Int, message: String)
    case decoding(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "네이버 검색 API 키가 없습니다. Config/Config.xcconfig의 Naver_Search_Client_ID/Secret을 확인해 주세요."
        case .invalidQuery: return "도착지 검색어를 입력해 주세요."
        case .invalidResponse: return "검색 서버의 응답 형식이 올바르지 않습니다."
        case .transport(let message): return "도착지 검색 중 네트워크 오류가 발생했습니다. (\(message))"
        case .httpStatus(let code, let message): return "네이버 검색 API가 \(code)를 반환했습니다. \(message)"
        case .decoding(let message): return "검색 결과를 해석하지 못했습니다. (\(message))"
        case .emptyResult: return "일치하는 도착지가 없습니다."
        }
    }
}

struct NaverLocationSearchService: NaverLocationSearchServicing {
    private let clientID: String
    private let clientSecret: String
    private let session: URLSession

    init(clientID: String = AppConfig.naverSearchClientID,
         clientSecret: String = AppConfig.naverSearchClientSecret,
         session: URLSession = .shared) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.session = session
    }

    func search(query: String, display: Int = 5) async throws -> [NaverLocation] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw NaverLocationSearchError.invalidQuery }
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw NaverLocationSearchError.missingCredentials
        }

        var components = URLComponents(string: "https://naverapihub.apigw.ntruss.com/search/v1/local")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "display", value: String(min(max(display, 1), 5))),
            URLQueryItem(name: "start", value: "1"),
            URLQueryItem(name: "sort", value: "random"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw NaverLocationSearchError.invalidQuery }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(clientID, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
        request.setValue(clientSecret, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NaverLocationSearchError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NaverLocationSearchError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorDTO.self, from: data)
            let message = apiError?.displayMessage ?? String(data: data, encoding: .utf8) ?? ""
            throw NaverLocationSearchError.httpStatus(code: http.statusCode, message: String(message.prefix(300)))
        }

        let dto: ResponseDTO
        do {
            dto = try JSONDecoder().decode(ResponseDTO.self, from: data)
        } catch {
            throw NaverLocationSearchError.decoding(error.localizedDescription)
        }

        let locations = dto.items.compactMap(Self.makeLocation)
        guard !locations.isEmpty else { throw NaverLocationSearchError.emptyResult }
        return locations
    }

    private static func makeLocation(_ item: ResponseDTO.ItemDTO) -> NaverLocation? {
        guard let longitudeValue = Double(item.mapx),
              let latitudeValue = Double(item.mapy) else { return nil }

        // API HUB는 WGS84 소수 문자열을 반환한다. 이관 초기/구형 응답의
        // 10^7 배 정수 좌표도 함께 처리해 잘못된 0,0 근처 좌표가 생기지 않게 한다.
        let latitude = abs(latitudeValue) > 90 ? latitudeValue / 10_000_000 : latitudeValue
        let longitude = abs(longitudeValue) > 180 ? longitudeValue / 10_000_000 : longitudeValue
        let coordinate = NaverCoordinate(latitude: latitude, longitude: longitude)
        guard (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else { return nil }

        return NaverLocation(title: item.title.removingHTMLTags,
                             category: item.category.removingHTMLTags,
                             description: item.description.removingHTMLTags,
                             roadAddress: item.roadAddress,
                             jibunAddress: item.address,
                             coordinate: coordinate,
                             link: URL(string: item.link))
    }

    private struct ResponseDTO: Decodable {
        var items: [ItemDTO]
        struct ItemDTO: Decodable {
            var title: String
            var link: String
            var category: String
            var description: String
            var address: String
            var roadAddress: String
            var mapx: String
            var mapy: String
        }
    }

    private struct APIErrorDTO: Decodable {
        var errorCode: String?
        var errorMessage: String?
        var code: String?
        var message: String?
        var errId: String?

        var displayMessage: String {
            let apiCode = errorCode ?? code
            let text = errorMessage ?? message ?? "요청에 실패했습니다."
            return [apiCode.map { "[\($0)]" }, text, errId.map { "(요청 ID: \($0))" }]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }
}

private extension String {
    var removingHTMLTags: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

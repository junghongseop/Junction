//
//  NaverGeocodingService.swift
//  DriveInGyeongbuk
//
//  주소 ↔ 좌표 변환.
//  - Geocoding         : 주소 문자열 → 좌표 (출발지/도착지 검색)
//  - Reverse Geocoding : 좌표 → 주소 (현재 위치 표시, 도착지 인근 행정구역 판정)
//
//  참고: NAVER Cloud Platform > Maps > Geocoding / Reverse Geocoding
//

import Foundation

enum NaverGeocodingLanguage: String {
    case korean = "kor"
    case english = "eng"
}

protocol NaverGeocodingServicing {
    /// 주소·장소 문자열을 좌표로 변환한다.
    /// - Parameters:
    ///   - query: 검색할 주소 (예: "경상북도 경주시 불국로 385")
    ///   - coordinate: 있으면 이 좌표에 가까운 결과가 우선 정렬된다.
    ///   - limit: 최대 결과 수 (1...100)
    func geocode(query: String,
                 near coordinate: NaverCoordinate?,
                 limit: Int,
                 language: NaverGeocodingLanguage) async throws -> [GeocodedPlace]

    /// 좌표를 주소로 변환한다.
    func reverseGeocode(coordinate: NaverCoordinate) async throws -> ReverseGeocodedAddress
}

extension NaverGeocodingServicing {
    func geocode(query: String,
                 near coordinate: NaverCoordinate?,
                 limit: Int) async throws -> [GeocodedPlace] {
        try await geocode(query: query,
                          near: coordinate,
                          limit: limit,
                          language: .korean)
    }

    func geocode(query: String) async throws -> [GeocodedPlace] {
        try await geocode(query: query, near: nil, limit: 10)
    }

    /// 첫 번째 결과만 필요할 때.
    func firstPlace(matching query: String, near coordinate: NaverCoordinate? = nil) async throws -> GeocodedPlace {
        let places = try await geocode(query: query, near: coordinate, limit: 1)
        guard let first = places.first else { throw NaverMapsError.emptyResult }
        return first
    }
}

// MARK: -

struct NaverGeocodingService: NaverGeocodingServicing {

    private let runner: NaverMapsRequestRunner

    init(configuration: NaverMapsConfiguration = .default,
         httpClient: NaverMapsHTTPClient = URLSessionNaverMapsHTTPClient()) {
        self.runner = NaverMapsRequestRunner(configuration: configuration, httpClient: httpClient)
    }

    // MARK: Geocoding

    func geocode(query: String,
                 near coordinate: NaverCoordinate? = nil,
                 limit: Int = 10,
                 language: NaverGeocodingLanguage = .korean) async throws -> [GeocodedPlace] {

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NaverMapsError.invalidRequest("검색어가 비어 있습니다.")
        }

        var queryItems = [
            URLQueryItem(name: "query", value: trimmed),
            URLQueryItem(name: "count", value: String(min(max(limit, 1), 100))),
            URLQueryItem(name: "language", value: language.rawValue)
        ]
        if let coordinate {
            queryItems.append(URLQueryItem(name: "coordinate", value: coordinate.apiQueryValue))
        }

        let request = try runner.makeRequest(host: runner.configuration.geocodingHost,
                                             path: runner.configuration.geocodePath,
                                             queryItems: queryItems)

        let dto = try await runner.send(request, as: NaverGeocodeResponseDTO.self)

        guard dto.status.uppercased() == "OK" else {
            throw NaverMapsError.api(code: dto.status,
                                     message: dto.errorMessage ?? "주소 검색에 실패했습니다.")
        }

        let places = (dto.addresses ?? []).compactMap(Self.makePlace(from:))
        guard !places.isEmpty else { throw NaverMapsError.emptyResult }
        return places
    }

    // MARK: Reverse Geocoding

    func reverseGeocode(coordinate: NaverCoordinate) async throws -> ReverseGeocodedAddress {

        let queryItems = [
            URLQueryItem(name: "coords", value: coordinate.apiQueryValue),
            URLQueryItem(name: "sourcecrs", value: "epsg:4326"),
            URLQueryItem(name: "orders", value: "roadaddr,addr,admcode"),
            URLQueryItem(name: "output", value: "json")
        ]

        let request = try runner.makeRequest(host: runner.configuration.geocodingHost,
                                             path: runner.configuration.reverseGeocodePath,
                                             queryItems: queryItems)

        let dto = try await runner.send(request, as: NaverReverseGeocodeResponseDTO.self)

        guard dto.status.code == 0 else {
            throw NaverMapsError.api(code: String(dto.status.code), message: dto.status.message)
        }
        guard let results = dto.results, !results.isEmpty else {
            throw NaverMapsError.emptyResult
        }

        return Self.makeAddress(from: results, coordinate: coordinate)
    }

    // MARK: - Mapping

    /// nil / 빈 문자열을 걸러내고 이어 붙인다. 남는 것이 없으면 nil.
    private static func joinNonEmpty(_ parts: [String?], separator: String = " ") -> String? {
        let kept = parts
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return kept.isEmpty ? nil : kept.joined(separator: separator)
    }

    private static func makePlace(from dto: NaverGeocodeResponseDTO.AddressDTO) -> GeocodedPlace? {
        guard let xString = dto.x, let yString = dto.y,
              let longitude = Double(xString), let latitude = Double(yString) else {
            return nil
        }

        let elements = dto.addressElements ?? []
        func element(_ type: String) -> String? {
            elements.first { $0.types?.contains(type) == true }?.longName?
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
        }

        return GeocodedPlace(
            coordinate: NaverCoordinate(latitude: latitude, longitude: longitude),
            roadAddress: dto.roadAddress ?? "",
            jibunAddress: dto.jibunAddress ?? "",
            englishAddress: dto.englishAddress ?? "",
            sido: element("SIDO"),
            sigungu: element("SIGUGUN"),
            placeName: element("BUILDING_NAME")
        )
    }

    private static func makeAddress(from results: [NaverReverseGeocodeResponseDTO.ResultDTO],
                                    coordinate: NaverCoordinate) -> ReverseGeocodedAddress {

        func result(named name: String) -> NaverReverseGeocodeResponseDTO.ResultDTO? {
            results.first { $0.name == name }
        }

        let roadResult = result(named: "roadaddr")
        let jibunResult = result(named: "addr")
        let region = roadResult?.region ?? jibunResult?.region ?? results.first?.region

        // 도로명 주소: "<시도> <시군구> <도로명> <건물번호>"
        var roadAddress: String?
        if let roadResult, let land = roadResult.land {
            let buildingNumber = Self.joinNonEmpty([land.number1, land.number2], separator: "-")
            roadAddress = Self.joinNonEmpty([
                roadResult.region?.area1?.name,
                roadResult.region?.area2?.name,
                land.name,
                buildingNumber
            ])
        }

        // 지번 주소: "<시도> <시군구> <읍면동> <번지>"
        var jibunAddress: String?
        if let jibunResult, let land = jibunResult.land {
            let lotNumber = Self.joinNonEmpty([land.number1, land.number2], separator: "-")
            jibunAddress = Self.joinNonEmpty([
                jibunResult.region?.area1?.name,
                jibunResult.region?.area2?.name,
                jibunResult.region?.area3?.name,
                lotNumber
            ])
        }

        return ReverseGeocodedAddress(
            coordinate: coordinate,
            roadAddress: roadAddress,
            jibunAddress: jibunAddress,
            sido: region?.area1?.name?.nilIfEmpty,
            sigungu: region?.area2?.name?.nilIfEmpty,
            eupmyeondong: region?.area3?.name?.nilIfEmpty,
            buildingName: roadResult?.land?.addition0?.value?.nilIfEmpty
        )
    }
}

// MARK: - Utility

extension String {
    /// 빈 문자열이면 nil.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

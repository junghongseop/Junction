//
//  ParkingAPIClient.swift
//  DriveInGyeongbuk
//
//  주차장 원천 데이터 클라이언트.
//
//  데이터 출처
//    GET https://junction-server.onrender.com/api/v1/parking-lots?latitude=&longitude=
//    → 현재 서버는 목적지에서 가장 가까운 주차장 한 곳을 객체로 준다.
//      구버전의 배열 응답도 계속 디코딩해 앱/서버 배포 순서가 달라도 동작하게 한다.
//
//  ⚠️ 서버가 주는 필드는 **주차장명 · 위도 · 경도 세 개뿐**이다.
//     요금 / 주차 면수 / 운영 시간 / 전화번호는 응답에 없어서 모델에도 두지 않았다.
//     나중에 서버가 필드를 늘리면 `ParkingLot` 과 `ParkingLotDTO` 에 함께 추가하면 된다.
//

import Foundation

/// 주차장 한 곳.
nonisolated struct ParkingLot: Identifiable, Hashable {

    /// 이름 + 좌표를 합친 안정적인 식별자.
    /// 매번 다시 조회해도 같은 주차장이면 같은 id 라서 SwiftUI 리스트가 깜빡이지 않는다.
    var id: String { "\(name)|\(coordinate.apiQueryValue)" }

    /// 주차장명 (예: "경상북도 포항시청 부설주차장").
    var name: String
    var coordinate: NaverCoordinate

    /// 서버가 한글 이름만 내려주므로 주차장 유형은 영어로 번역하고 지명은 로마자로 표기한다.
    var englishDisplayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unnamed Parking Lot" }

        var translated = trimmed
        let parkingTerms = [
            ("공영주차장", " Public Parking Lot "),
            ("부설주차장", " Parking Lot "),
            ("주차타워", " Parking Tower "),
            ("주차장", " Parking Lot ")
        ]
        for (korean, english) in parkingTerms {
            translated = translated.replacingOccurrences(of: korean, with: english)
        }

        if translated.containsHangul,
           let latin = translated.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) {
            translated = latin
        }

        return translated
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .capitalized(with: Locale(identifier: "en_US"))
    }
}

private extension String {
    var containsHangul: Bool {
        unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
                || (0x1100...0x11FF).contains(scalar.value)
                || (0x3130...0x318F).contains(scalar.value)
        }
    }
}

protocol ParkingAPIClientProtocol {
    /// 목적지 주변 주차장을 조회한다.
    ///
    /// 검색 반경은 서버에서 2km 로 고정되어 있어 인자로 받지 않는다.
    /// (`JunctionServerConfiguration.fixedSearchRadiusMeters`)
    /// 더 좁게 보고 싶으면 `ParkingService` 처럼 결과를 받은 뒤 잘라내면 된다.
    func fetchParkingLots(around coordinate: NaverCoordinate) async throws -> [ParkingLot]
}

// MARK: -

struct ParkingAPIClient: ParkingAPIClientProtocol {

    private let runner: JunctionServerRequestRunner
    private let configuration: JunctionServerConfiguration

    init(configuration: JunctionServerConfiguration = .default,
         httpClient: JunctionServerHTTPClient = URLSessionJunctionServerHTTPClient()) {
        self.configuration = configuration
        self.runner = JunctionServerRequestRunner(configuration: configuration, httpClient: httpClient)
    }

    func fetchParkingLots(around coordinate: NaverCoordinate) async throws -> [ParkingLot] {
        let request = try runner.makeDestinationRequest(path: configuration.parkingLotsPath,
                                                        coordinate: coordinate)
        let dto = try await runner.send(request, as: ParkingLotsResponseDTO.self)
        // 좌표가 숫자로 해석되지 않는 레코드는 지도에 찍을 수 없으니 버린다.
        return dto.parking.compactMap(Self.makeLot(from:))
    }

    // MARK: - Mapping

    private static func makeLot(from dto: ParkingLotsResponseDTO.ParkingLotDTO) -> ParkingLot? {
        // 현재 서버는 문자열로 주지만 숫자로 바뀌어도 DTO가 문자열로 정규화한다.
        guard let latitudeText = dto.latitude,
              let longitudeText = dto.longitude,
              let latitude = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
              let longitude = Double(longitudeText.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        let name = dto.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParkingLot(name: name.isEmpty ? "이름 없는 주차장" : name,
                          coordinate: NaverCoordinate(latitude: latitude, longitude: longitude))
    }
}

// MARK: - DTO

/// `GET /api/v1/parking-lots` 응답.
struct ParkingLotsResponseDTO: Decodable {
    var parking: [ParkingLotDTO]

    private enum CodingKeys: String, CodingKey {
        case parking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if try container.decodeNil(forKey: .parking) {
            parking = []
        } else if let lots = try? container.decode([ParkingLotDTO].self, forKey: .parking) {
            parking = lots
        } else {
            // 현재 운영 서버 응답: { "parking": { ... } }
            parking = [try container.decode(ParkingLotDTO.self, forKey: .parking)]
        }
    }

    struct ParkingLotDTO: Decodable {
        var name: String
        /// WGS84 위도. 문자열/JSON 숫자를 모두 받아 문자열로 정규화한다.
        var latitude: String?
        /// WGS84 경도. 문자열/JSON 숫자를 모두 받아 문자열로 정규화한다.
        var longitude: String?

        private enum CodingKeys: String, CodingKey {
            case name, latitude, longitude
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = (try? container.decode(String.self, forKey: .name)) ?? ""
            latitude = Self.coordinateText(for: .latitude, in: container)
            longitude = Self.coordinateText(for: .longitude, in: container)
        }

        private static func coordinateText(
            for key: CodingKeys,
            in container: KeyedDecodingContainer<CodingKeys>
        ) -> String? {
            if let text = try? container.decode(String.self, forKey: key) {
                return text
            }
            if let number = try? container.decode(Double.self, forKey: key) {
                return String(number)
            }
            return nil
        }
    }
}

//
//  ParkingAPIClient.swift
//  DriveInGyeongbuk
//
//  주차장 원천 데이터 클라이언트.
//
//  데이터 출처
//    GET https://junction-server.onrender.com/api/v1/parking-lots?latitude=&longitude=
//    → 목적지 반경 2km 안에서 현재 운영 중인 경상북도 주차장을 거리순으로 준다.
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
        // 위/경도가 숫자가 아니라 **문자열**로 내려온다.
        guard let latitude = Double(dto.latitude.trimmingCharacters(in: .whitespaces)),
              let longitude = Double(dto.longitude.trimmingCharacters(in: .whitespaces)) else {
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

    struct ParkingLotDTO: Decodable {
        var name: String
        /// WGS84 위도 **문자열**.
        var latitude: String
        /// WGS84 경도 **문자열**.
        var longitude: String
    }
}

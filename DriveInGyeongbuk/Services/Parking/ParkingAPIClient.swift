//
//  ParkingAPIClient.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  주차장 원천 데이터 클라이언트.
//  후보 소스
//    - 공공데이터포털 : 전국주차장정보 표준데이터
//    - 경상북도 / 시군 자체 개방 데이터
//

import Foundation

/// 주차장 한 곳.
struct ParkingLot: Identifiable, Hashable {
    var id = UUID()

    var name: String
    var coordinate: NaverCoordinate
    var address: String?
    var kind: Kind
    var feeKind: FeeKind
    /// 총 주차 면수.
    var totalCapacity: Int?
    /// 기본 요금(원) / 기본 시간(분).
    var baseFee: Int?
    var baseMinutes: Int?
    /// 운영 시간 안내 문구.
    var operatingHours: String?
    var phoneNumber: String?

    enum Kind: String, Hashable {
        case publicLot
        case privateLot
        case roadside
        case unknown
    }

    enum FeeKind: String, Hashable {
        case free
        case paid
        case mixed
        case unknown
    }
}

protocol ParkingAPIClientProtocol {
    /// 좌표 반경 내 주차장을 조회한다.
    func fetchParkingLots(around coordinate: NaverCoordinate,
                          radiusMeters: Int) async throws -> [ParkingLot]
}

// MARK: - Stub

/// TODO: 공공데이터포털 서비스 키 발급 후 실제 호출 구현.
struct ParkingAPIClient: ParkingAPIClientProtocol {

    init() {}

    func fetchParkingLots(around coordinate: NaverCoordinate,
                          radiusMeters: Int) async throws -> [ParkingLot] {
        // TODO: 표준데이터 조회 → ParkingLot 매핑.
        []
    }
}

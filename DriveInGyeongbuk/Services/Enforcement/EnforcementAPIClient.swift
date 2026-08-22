//
//  EnforcementAPIClient.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  주정차 단속 구간 원천 데이터 클라이언트.
//  후보 소스
//    - 공공데이터포털 : 주정차금지 구간 / 단속 CCTV 표준데이터
//    - 각 시군 개방 데이터 (경주시, 포항시, 안동시 …)
//

import Foundation

/// 주정차 단속 구간.
struct EnforcementZone: Identifiable, Hashable {
    var id = UUID()

    var name: String
    /// 구간 중심 좌표.
    var coordinate: NaverCoordinate
    /// 구간을 이루는 좌표열. 폴리라인으로 그릴 때 쓴다.
    var polyline: [NaverCoordinate]
    var kind: Kind
    /// 단속 시간대 안내 문구 (예: "평일 08:00~20:00").
    var enforcementHours: String?
    /// 데이터를 제공한 지자체.
    var authority: String?

    enum Kind: String, Hashable {
        /// 주정차 절대 금지
        case noStopping
        /// 주차 금지(정차는 가능)
        case noParking
        /// 어린이 보호구역
        case schoolZone
        /// 소방시설 주변
        case fireZone
        /// 고정형 단속 카메라
        case fixedCamera
        case unknown
    }
}

protocol EnforcementAPIClientProtocol {
    /// 좌표 반경 내 단속 구간을 조회한다.
    func fetchEnforcementZones(around coordinate: NaverCoordinate,
                               radiusMeters: Int) async throws -> [EnforcementZone]
}

// MARK: - Stub

/// TODO: 공공데이터포털 서비스 키 발급 후 실제 호출 구현.
struct EnforcementAPIClient: EnforcementAPIClientProtocol {

    init() {}

    func fetchEnforcementZones(around coordinate: NaverCoordinate,
                               radiusMeters: Int) async throws -> [EnforcementZone] {
        // TODO: 표준데이터 조회 → EnforcementZone 매핑.
        []
    }
}

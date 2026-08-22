//
//  SpeedLimitDataSource.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  제한속도 원천 데이터 공급자.
//  후보 소스
//    - 국가교통정보센터(ITS) 오픈 API : 안전운행 정보 / 단속 카메라
//    - 공공데이터포털 : 전국 무인교통단속카메라 표준 데이터
//    - 번들 내장 데이터셋(오프라인 폴백)
//

import Foundation

/// 제한속도 정보 한 건.
struct SpeedLimitInfo: Identifiable, Hashable {
    var id = UUID()

    /// 제한속도가 적용되는 지점.
    var coordinate: NaverCoordinate
    /// 제한속도(km/h).
    var limitKPH: Int
    /// 도로명. `DrivingRoute.sections` 의 `name` 과 매칭한다.
    var roadName: String?
    /// 적용 구간 길이(m). 구간단속이면 값이 있다.
    var sectionLengthMeters: Int?
    var kind: Kind

    enum Kind: String, Hashable {
        /// 일반 제한속도 표지
        case regulatory
        /// 고정식 단속 카메라
        case fixedCamera
        /// 구간 단속
        case sectionCamera
        /// 어린이 보호구역
        case schoolZone
        /// 노인 보호구역
        case silverZone
    }
}

/// 제한속도 데이터를 가져오는 방법을 추상화한다.
protocol SpeedLimitDataSource {
    /// 경로 전체에 대한 제한속도 정보를 가져온다.
    func speedLimits(along route: DrivingRoute) async throws -> [SpeedLimitInfo]

    /// 특정 좌표 주변의 제한속도 정보를 가져온다.
    func speedLimits(around coordinate: NaverCoordinate, radiusMeters: Int) async throws -> [SpeedLimitInfo]
}

// MARK: - Stub

/// TODO: ITS / 공공데이터포털 연동으로 교체.
struct RemoteSpeedLimitDataSource: SpeedLimitDataSource {

    init() {}

    func speedLimits(along route: DrivingRoute) async throws -> [SpeedLimitInfo] {
        // TODO: route.sections 의 도로명·좌표로 제한속도 데이터를 조회한다.
        []
    }

    func speedLimits(around coordinate: NaverCoordinate, radiusMeters: Int) async throws -> [SpeedLimitInfo] {
        // TODO: 좌표 반경 검색 API 연동.
        []
    }
}

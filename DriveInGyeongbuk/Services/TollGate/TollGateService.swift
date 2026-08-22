//
//  TollGateService.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  톨게이트 차로 안내.
//  렌터카를 탄 외국인이 가장 많이 당황하는 지점 — 하이패스 전용 차로로
//  잘못 들어가지 않도록 "몇 번째 차로로 붙어야 하는지"를 미리 알려준다.
//
//  입력은 `DrivingRoute.tollGateSteps`.
//

import Foundation

/// 톨게이트 차로 종류.
enum TollLaneType: String, Hashable {
    /// 하이패스 전용
    case hipass
    /// 일반(현금/카드)
    case cash
    /// 하이패스 + 일반 겸용
    case hybrid
    /// 화물차 전용
    case truck
}

/// 톨게이트 한 곳의 정보.
struct TollGate: Identifiable, Hashable {
    var id = UUID()

    var name: String
    var coordinate: NaverCoordinate
    /// 왼쪽부터 순서대로의 차로 구성.
    var lanes: [TollLaneType]
    /// 통과 요금(원). 모르면 nil.
    var fare: Int?
}

/// 특정 톨게이트에서 사용자에게 줄 안내.
struct TollGateGuidance: Identifiable, Hashable {
    var id = UUID()

    var tollGate: TollGate
    /// 현재 위치에서 남은 거리(m).
    var distanceAheadMeters: Int
    /// 권장 차로 (왼쪽부터 1-based).
    var recommendedLaneNumbers: [Int]
    var recommendedLaneType: TollLaneType
    /// 한국어 안내 문구.
    var koreanMessage: String
    /// 외국어 안내 문구.
    var localizedMessage: String
}

protocol TollGateServicing {
    /// 하이패스 단말이 있는 차량인지. 안내 차로가 달라진다.
    var hasHipassDevice: Bool { get set }

    /// 경로 상의 톨게이트 목록을 미리 불러온다.
    func prepare(for route: DrivingRoute) async throws

    /// 현재 위치 기준으로 다가오는 톨게이트 안내를 만든다.
    func guidance(at coordinate: NaverCoordinate) -> TollGateGuidance?
}

// MARK: - Stub

/// TODO: 한국도로공사 영업소/차로 데이터 연동 후 구현.
final class TollGateService: TollGateServicing {

    var hasHipassDevice: Bool = false

    /// 안내를 시작할 남은 거리(m). 고속 주행을 감안해 넉넉히 잡는다.
    var alertLeadDistanceMeters: Int = 1500

    private var tollGates: [TollGate] = []
    private var route: DrivingRoute?

    init(hasHipassDevice: Bool = false) {
        self.hasHipassDevice = hasHipassDevice
    }

    func prepare(for route: DrivingRoute) async throws {
        // TODO: route.tollGateSteps 의 좌표/문구를 실제 영업소 데이터와 매칭한다.
        self.route = route
        self.tollGates = []
    }

    func guidance(at coordinate: NaverCoordinate) -> TollGateGuidance? {
        // TODO: 1) 앞쪽 가장 가까운 톨게이트 탐색
        //       2) alertLeadDistanceMeters 이내면 안내 생성
        //       3) hasHipassDevice 에 따라 hipass / cash 차로 추천
        nil
    }
}

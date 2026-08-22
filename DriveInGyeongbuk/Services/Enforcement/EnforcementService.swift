//
//  EnforcementService.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  도착지 근처 주정차 단속 구간 안내.
//  "여기 세우면 과태료"를 도착 전에 미리 알려주는 것이 목적.
//

import Foundation

/// 사용자에게 띄울 단속 구간 경고.
struct EnforcementWarning: Identifiable, Hashable {
    var id = UUID()

    var zone: EnforcementZone
    /// 현재 위치에서의 거리(m).
    var distanceMeters: Int
    /// 지금 시각이 단속 시간대인지.
    var isCurrentlyEnforced: Bool
    /// 한국어 안내 문구.
    var koreanMessage: String
    /// 외국어 안내 문구.
    var localizedMessage: String
}

protocol EnforcementServicing {
    /// 도착지 근처 단속 구간을 가져온다.
    func zones(near destination: NaverCoordinate,
               radiusMeters: Int) async throws -> [EnforcementZone]

    /// 현재 위치 기준 경고를 만든다. 없으면 빈 배열.
    func warnings(at coordinate: NaverCoordinate, date: Date) -> [EnforcementWarning]
}

// MARK: - Stub

/// TODO: 시간대 판정 + 폴리라인 근접 판정 구현.
final class EnforcementService: EnforcementServicing {

    /// 경고를 띄울 거리(m).
    var warningRadiusMeters: Int = 150

    private let apiClient: EnforcementAPIClientProtocol
    private var cachedZones: [EnforcementZone] = []

    init(apiClient: EnforcementAPIClientProtocol = EnforcementAPIClient()) {
        self.apiClient = apiClient
    }

    func zones(near destination: NaverCoordinate,
               radiusMeters: Int = 1000) async throws -> [EnforcementZone] {
        // TODO: 캐싱 후 반환.
        cachedZones = try await apiClient.fetchEnforcementZones(around: destination,
                                                               radiusMeters: radiusMeters)
        return cachedZones
    }

    func warnings(at coordinate: NaverCoordinate, date: Date = .now) -> [EnforcementWarning] {
        // TODO: 1) cachedZones 중 warningRadiusMeters 이내 구간 필터
        //       2) enforcementHours 파싱해 현재 단속 시간대인지 판정
        //       3) 안내 문구 생성 (RoadSignExplanationService 재사용)
        []
    }
}

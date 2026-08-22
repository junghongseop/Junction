//
//  SpeedLimitService.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  주행 중 제한속도 안내.
//  `NaverDirectionsService` 가 만든 `DrivingRoute` 와 현재 위치를 받아
//  "지금 이 도로의 제한속도는 얼마인지 / 초과했는지"를 알려준다.
//

import Foundation

/// 사용자에게 띄울 제한속도 안내.
struct SpeedLimitAlert: Identifiable, Hashable {
    var id = UUID()

    var limit: SpeedLimitInfo
    /// 현재 위치에서 해당 지점까지 남은 거리(m).
    var distanceAheadMeters: Int
    /// 현재 속도(km/h).
    var currentSpeedKPH: Int
    var severity: Severity

    enum Severity: String, Hashable {
        /// 곧 제한속도 구간에 진입한다.
        case upcoming
        /// 제한속도를 넘었다.
        case exceeding
    }
}

protocol SpeedLimitServicing {
    /// 경로에 대한 제한속도 정보를 미리 불러온다. (내비 시작 시 1회)
    func prepare(for route: DrivingRoute) async throws

    /// 현재 위치/속도 기준 안내를 만든다. 안내할 게 없으면 nil.
    func alert(at coordinate: NaverCoordinate, speedKPH: Int) -> SpeedLimitAlert?

    /// 현재 위치의 제한속도(km/h). 모르면 nil.
    func currentLimitKPH(at coordinate: NaverCoordinate) -> Int?
}

// MARK: - Stub

/// TODO: 실제 매칭 로직 구현.
final class SpeedLimitService: SpeedLimitServicing {

    private let dataSource: SpeedLimitDataSource
    private var limits: [SpeedLimitInfo] = []
    private var route: DrivingRoute?

    /// 안내를 시작할 남은 거리(m).
    var alertLeadDistanceMeters: Int = 300
    /// 초과로 판정할 허용 오차(km/h).
    var toleranceKPH: Int = 5

    init(dataSource: SpeedLimitDataSource = RemoteSpeedLimitDataSource()) {
        self.dataSource = dataSource
    }

    func prepare(for route: DrivingRoute) async throws {
        // TODO: 경로 제한속도 프리페치 + 경로 진행순 정렬.
        self.route = route
        self.limits = try await dataSource.speedLimits(along: route)
    }

    func alert(at coordinate: NaverCoordinate, speedKPH: Int) -> SpeedLimitAlert? {
        // TODO: 1) 진행 방향 앞쪽 제한속도 지점 탐색
        //       2) alertLeadDistanceMeters 이내면 .upcoming
        //       3) 현재 제한속도 + toleranceKPH 초과면 .exceeding
        nil
    }

    func currentLimitKPH(at coordinate: NaverCoordinate) -> Int? {
        // TODO: 현재 위치를 경로에 스냅한 뒤 해당 구간의 제한속도를 반환.
        nil
    }
}

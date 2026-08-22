//
//  ParkingService.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  도착지 근처 주차장 안내.
//  도착지 반경 안에 들어오면(`arrivalRadiusMeters`) 인근 주차장을 거리순으로
//  보여 준다. 무료/유료, 운영 시간까지 함께 안내하는 것이 목표.
//

import Foundation

/// 사용자에게 보여줄 주차장 추천 한 건.
struct ParkingSuggestion: Identifiable, Hashable {
    var id = UUID()

    var lot: ParkingLot
    /// 도착지로부터의 직선 거리(m).
    var distanceFromDestinationMeters: Int
    /// 도보 예상 시간(분).
    var walkingMinutes: Int?
}

protocol ParkingServicing {
    /// 도착지 근처로 판정할 반경(m).
    var arrivalRadiusMeters: Int { get set }

    /// 도착지 근처 주차장을 거리순으로 가져온다.
    func suggestions(near destination: NaverCoordinate,
                     radiusMeters: Int) async throws -> [ParkingSuggestion]

    /// 현재 위치가 도착지 근처인지.
    func isNearDestination(_ coordinate: NaverCoordinate, destination: NaverCoordinate) -> Bool
}

// MARK: - Stub

/// TODO: 정렬/도보시간 계산/캐싱 구현.
final class ParkingService: ParkingServicing {

    var arrivalRadiusMeters: Int = 1000

    private let apiClient: ParkingAPIClientProtocol

    init(apiClient: ParkingAPIClientProtocol = ParkingAPIClient()) {
        self.apiClient = apiClient
    }

    func suggestions(near destination: NaverCoordinate,
                     radiusMeters: Int = 1000) async throws -> [ParkingSuggestion] {
        // TODO: apiClient 결과를 거리순 정렬하고 도보 시간을 계산한다.
        _ = try await apiClient.fetchParkingLots(around: destination, radiusMeters: radiusMeters)
        return []
    }

    func isNearDestination(_ coordinate: NaverCoordinate, destination: NaverCoordinate) -> Bool {
        coordinate.distance(to: destination) <= Double(arrivalRadiusMeters)
    }
}

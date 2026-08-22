//
//  ParkingService.swift
//  DriveInGyeongbuk
//
//  도착지 근처 주차장 안내.
//  도착지 반경 안에 들어오면(`arrivalRadiusMeters`) 인근 주차장을 거리순으로 보여 준다.
//
//  서버(`ParkingAPIClient`)는 반경 2km 안의 주차장을 **이미 거리순으로** 준다.
//  이 서비스가 더 하는 일은 세 가지다.
//    1. 요청한 반경(≤2km)으로 잘라내기
//    2. 도착지로부터의 직선 거리 · 도보 예상 시간 계산
//    3. 같은 목적지 주변을 반복 조회할 때 서버를 다시 때리지 않도록 캐싱
//

import Foundation

/// 사용자에게 보여줄 주차장 추천 한 건.
nonisolated struct ParkingSuggestion: Identifiable, Hashable {

    var id: String { lot.id }

    var lot: ParkingLot
    /// 도착지로부터의 직선 거리(m).
    var distanceFromDestinationMeters: Int
    /// 도보 예상 시간(분).
    var walkingMinutes: Int?

    /// 사람이 읽는 거리 표기.
    var distanceDescription: String {
        distanceFromDestinationMeters >= 1000
            ? String(format: "%.1f km", Double(distanceFromDestinationMeters) / 1000)
            : "\(distanceFromDestinationMeters) m"
    }
}

protocol ParkingServicing {
    /// 도착지 근처로 판정할 반경(m).
    var arrivalRadiusMeters: Int { get set }

    /// 도착지 근처 주차장을 거리순으로 가져온다.
    ///
    /// - Parameter radiusMeters: 서버 검색 반경(2km)보다 크게 넣어도 2km 로 잘린다.
    func suggestions(near destination: NaverCoordinate,
                     radiusMeters: Int) async throws -> [ParkingSuggestion]

    /// 현재 위치가 도착지 근처인지.
    func isNearDestination(_ coordinate: NaverCoordinate, destination: NaverCoordinate) -> Bool
}

// MARK: -

final class ParkingService: ParkingServicing {

    /// 도착지 근처로 판정할 반경(m).
    var arrivalRadiusMeters: Int = 1000

    /// 도보 속도(km/h). 성인 평균 보행 속도.
    var walkingSpeedKPH: Double = 4.0

    /// 직선 거리를 실제 도보 거리로 보정하는 계수.
    /// 골목을 돌아가야 하므로 직선보다 3할쯤 길다고 본다.
    var walkingDetourFactor: Double = 1.3

    /// 캐시를 재사용할 최대 시간(초).
    var cacheLifetime: TimeInterval = 600

    /// 캐시 중심에서 이 거리 안이면 같은 목적지로 보고 캐시를 재사용한다.
    ///
    /// 서버가 중심 기준 2km 를 주므로, 중심이 조금 움직여도 요청 반경만큼은
    /// 여전히 캐시 안에 다 들어 있어야 한다. 넉넉하게 300m 로 잡았다.
    var cacheReuseRadiusMeters: Double = 300

    private let apiClient: ParkingAPIClientProtocol
    private var cache: Cache?

    private struct Cache {
        var center: NaverCoordinate
        var lots: [ParkingLot]
        var fetchedAt: Date
    }

    init(apiClient: ParkingAPIClientProtocol = ParkingAPIClient()) {
        self.apiClient = apiClient
    }

    // MARK: 조회

    func suggestions(near destination: NaverCoordinate,
                     radiusMeters: Int = 1000) async throws -> [ParkingSuggestion] {

        let lots = try await parkingLots(near: destination)

        // 서버 반경(2km)보다 넓게 요청해도 실제로 받은 만큼만 쓸 수 있다.
        let limit = Double(min(max(radiusMeters, 0), JunctionServerConfiguration.fixedSearchRadiusMeters))

        return lots
            .map { lot -> ParkingSuggestion in
                let distance = lot.coordinate.distance(to: destination)
                return ParkingSuggestion(lot: lot,
                                         distanceFromDestinationMeters: Int(distance.rounded()),
                                         walkingMinutes: walkingMinutes(forDistanceMeters: distance))
            }
            .filter { Double($0.distanceFromDestinationMeters) <= limit }
            // 서버도 거리순으로 주지만, 서버의 기준점과 목적지가 미세하게 다를 수 있어 다시 정렬한다.
            .sorted { $0.distanceFromDestinationMeters < $1.distanceFromDestinationMeters }
    }

    func isNearDestination(_ coordinate: NaverCoordinate, destination: NaverCoordinate) -> Bool {
        coordinate.distance(to: destination) <= Double(arrivalRadiusMeters)
    }

    /// 캐시를 비운다. 목적지를 바꾸면 호출한다.
    func clearCache() {
        cache = nil
    }

    // MARK: 내부

    /// 캐시가 살아 있으면 그대로, 아니면 서버에서 새로 받아 온다.
    private func parkingLots(near destination: NaverCoordinate) async throws -> [ParkingLot] {
        if let cache,
           Date.now.timeIntervalSince(cache.fetchedAt) < cacheLifetime,
           cache.center.distance(to: destination) <= cacheReuseRadiusMeters {
            return cache.lots
        }

        let lots = try await apiClient.fetchParkingLots(around: destination)
        cache = Cache(center: destination, lots: lots, fetchedAt: .now)
        return lots
    }

    /// 직선 거리로 도보 시간을 추정한다.
    ///
    /// 서버가 도보 경로를 주지 않아 어림값이다. 실제 경로 기반 도보 시간이 필요해지면
    /// 네이버 Directions 의 보행자 옵션으로 바꿔야 한다.
    private func walkingMinutes(forDistanceMeters distance: Double) -> Int? {
        guard distance.isFinite, distance >= 0 else { return nil }
        let walkingMeters = distance * walkingDetourFactor
        let minutes = walkingMeters / (walkingSpeedKPH * 1000 / 60)
        return max(1, Int(minutes.rounded()))
    }
}

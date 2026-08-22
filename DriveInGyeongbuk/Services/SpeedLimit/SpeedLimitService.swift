//
//  SpeedLimitService.swift
//  DriveInGyeongbuk
//
//  주행 중 제한속도 안내.
//
//  하는 일
//    1. `prepare(for:)` — 경로 전체를 미리 제한속도 구간으로 쪼개 둔다. (내비 시작 시 1회)
//    2. `currentLimitKPH(at:)` — 현재 위치의 제한속도.
//    3. `alert(at:speedKPH:)` — 초과 경고 / 감속 예고.
//
//  왜 미리 쪼개 두는가
//    주행 중에는 위치 갱신이 초당 1회씩 들어온다. 그때마다 SQLite 를 때리면 느리고
//    배터리도 먹는다. 경로가 정해지는 순간 필요한 링크를 한 번에 읽어 메모리에 올려 두면
//    이후 조회는 전부 계산만으로 끝난다. (경로 200km 기준 링크 수천 개, 수 MB 수준)
//
//  경로 없이 주행하는 경우
//    `prepare(around:radiusMeters:)` 로 현재 위치 주변만 올려 두고 쓴다.
//    반경을 벗어나면 `needsRefresh(at:)` 가 true 가 되므로 다시 부르면 된다.
//

import Foundation

/// 경로를 제한속도가 같은 구간들로 쪼갠 것.
struct RouteSpeedLimitSegment: Identifiable, Hashable {
    var id = UUID()

    /// `DrivingRoute.path` 상의 시작/끝 인덱스(양끝 포함).
    var startPathIndex: Int
    var endPathIndex: Int

    /// 제한속도(km/h). 매칭되는 링크를 못 찾았으면 nil.
    var limitKPH: Int?
    var roadName: String?
    var roadRank: RoadRank

    /// 경로 출발점에서 이 구간 진입까지의 거리(m).
    var distanceFromStartMeters: Double
    /// 구간 길이(m).
    var lengthMeters: Double

    /// 이 구간을 대표하는 링크 ID. 디버깅·지도 강조용.
    var representativeLinkID: Int64?

    /// 경로 출발점에서 이 구간이 끝나는 지점까지의 거리(m).
    var endDistanceFromStartMeters: Double { distanceFromStartMeters + lengthMeters }

    /// 초과 경고를 띄워도 되는 구간인지.
    /// 표준노드링크가 이면도로에 넣어 둔 10~20km/h 는 표지판 값이 아니라 오탐이 된다.
    var isReliableLimit: Bool {
        guard let limitKPH else { return false }
        return limitKPH >= 30
    }

    var displayName: String {
        if let roadName, !roadName.isEmpty { return roadName }
        return roadRank.koreanTitle
    }
}

/// 사용자에게 띄울 제한속도 안내.
struct SpeedLimitAlert: Identifiable, Hashable {
    var id = UUID()

    var severity: Severity
    /// 안내 대상 제한속도(km/h).
    var limitKPH: Int
    /// 해당 구간의 도로명.
    var roadName: String?
    var roadRank: RoadRank
    /// 현재 위치에서 해당 구간까지 남은 거리(m). 이미 그 구간 안이면 0.
    var distanceAheadMeters: Int
    /// 현재 속도(km/h).
    var currentSpeedKPH: Int

    enum Severity: String, Hashable {
        /// 곧 더 낮은 제한속도 구간에 진입한다.
        case upcoming
        /// 제한속도를 넘었다.
        case exceeding
    }

    /// 제한속도를 얼마나 넘었는지(km/h). 넘지 않았으면 0.
    var excessKPH: Int { max(0, currentSpeedKPH - limitKPH) }

    var koreanMessage: String {
        switch severity {
        case .exceeding:
            return "제한속도 \(limitKPH)km/h · \(excessKPH)km/h 초과"
        case .upcoming:
            let distance = distanceAheadMeters >= 1000
                ? String(format: "%.1fkm", Double(distanceAheadMeters) / 1000)
                : "\(distanceAheadMeters)m"
            return "\(distance) 앞 제한속도 \(limitKPH)km/h"
        }
    }

    /// 외국인 운전자용 영문 문구.
    var englishMessage: String {
        switch severity {
        case .exceeding:
            return "Speed limit \(limitKPH) km/h — you are \(excessKPH) km/h over"
        case .upcoming:
            let distance = distanceAheadMeters >= 1000
                ? String(format: "%.1f km", Double(distanceAheadMeters) / 1000)
                : "\(distanceAheadMeters) m"
            return "Speed limit \(limitKPH) km/h in \(distance)"
        }
    }
}

// MARK: -

protocol SpeedLimitServicing {

    /// 경로에 대한 제한속도 정보를 미리 불러온다. (내비 시작 시 1회)
    func prepare(for route: DrivingRoute) async throws

    /// 경로 없이 현재 위치 주변만 불러온다. (자유 주행)
    func prepare(around coordinate: NaverCoordinate, radiusMeters: Double) async throws

    /// 현재 위치의 제한속도(km/h). 모르면 nil.
    func currentLimitKPH(at coordinate: NaverCoordinate) -> Int?

    /// 현재 위치가 스냅된 도로 링크. 도로명·등급까지 필요할 때 쓴다.
    func currentMatch(at coordinate: NaverCoordinate) -> SpeedLimitMatch?

    /// 현재 위치/속도 기준 안내를 만든다. 안내할 게 없으면 nil.
    func alert(at coordinate: NaverCoordinate, speedKPH: Int) -> SpeedLimitAlert?

    /// 경로를 쪼갠 제한속도 구간. 경로 준비 전이면 빈 배열.
    var routeSegments: [RouteSpeedLimitSegment] { get }
}

extension SpeedLimitServicing {
    func prepare(around coordinate: NaverCoordinate) async throws {
        try await prepare(around: coordinate, radiusMeters: 3000)
    }
}

// MARK: -

final class SpeedLimitService: SpeedLimitServicing {

    // MARK: 튜닝 값

    /// 안내를 시작할 남은 거리(m).
    var alertLeadDistanceMeters: Double = 300
    /// 초과로 판정할 허용 오차(km/h). GPS 속도 오차와 계기판 오차를 감안한 값이다.
    var toleranceKPH: Int = 5
    /// 현재 위치를 도로 링크에 붙일 때 허용할 최대 수직 거리(m).
    /// 도심 GPS 오차(15~20m)와 왕복 도로 폭을 감안했다.
    var matchToleranceMeters: Double = 35
    /// 이보다 짧은 구간은 앞 구간에 흡수시킨다. 교차로 근처에서 구간이 잘게 쪼개지는 걸 막는다.
    var minimumSegmentLengthMeters: Double = 40
    /// 경로 링크를 읽어 올 때 경로 좌우로 확보할 폭(m).
    var routeCorridorMeters: Double = 60

    // MARK: 상태

    private let dataSource: SpeedLimitDataSource

    private(set) var routeSegments: [RouteSpeedLimitSegment] = []

    private var route: DrivingRoute?
    /// 경로 각 점의 평면 좌표.
    private var projectedRoutePath: [UTMKPoint] = []
    /// 경로 출발점에서 각 점까지의 누적 거리(m).
    private var cumulativeDistances: [Double] = []
    /// 경로 없이 주행할 때 쓰는 주변 링크 인덱스.
    private var localIndex: SpeedLimitLinkIndex?
    /// `prepare(around:)` 로 올려 둔 영역의 중심과 반경.
    private var localCenter: UTMKPoint?
    private var localRadiusMeters: Double = 0

    /// 직전에 매칭된 경로 인덱스. 주행 중에는 위치가 조금씩만 움직이므로
    /// 이 값 주변부터 훑으면 전체 탐색을 피할 수 있다.
    private var lastPathIndex: Int?

    init(dataSource: SpeedLimitDataSource) {
        self.dataSource = dataSource
    }

    /// 번들 DB 를 쓰는 기본 구성. DB 를 못 열면 에러를 던진다.
    convenience init() throws {
        self.init(dataSource: try SQLiteSpeedLimitDataSource())
    }

    // MARK: - 준비

    func prepare(for route: DrivingRoute) async throws {
        guard !route.path.isEmpty else {
            reset()
            return
        }

        let links = try await dataSource.links(along: route, corridorMeters: routeCorridorMeters)

        let projectedPath = route.path.map(KoreaCoordinateConverter.project)
        let distances = Self.cumulativeDistances(of: projectedPath)
        let index = SpeedLimitLinkIndex(links: links)

        self.route = route
        self.projectedRoutePath = projectedPath
        self.cumulativeDistances = distances
        self.localIndex = index
        self.localCenter = nil
        self.localRadiusMeters = 0
        self.lastPathIndex = nil
        self.routeSegments = makeSegments(projectedPath: projectedPath,
                                          distances: distances,
                                          index: index)
    }

    func prepare(around coordinate: NaverCoordinate, radiusMeters: Double) async throws {
        let links = try await dataSource.links(around: coordinate, radiusMeters: radiusMeters)

        route = nil
        projectedRoutePath = []
        cumulativeDistances = []
        routeSegments = []
        lastPathIndex = nil
        localIndex = SpeedLimitLinkIndex(links: links)
        localCenter = KoreaCoordinateConverter.project(coordinate)
        localRadiusMeters = radiusMeters
    }

    /// 자유 주행 모드에서 올려 둔 영역을 벗어났는지.
    /// true 면 `prepare(around:)` 를 다시 불러야 한다.
    func needsRefresh(at coordinate: NaverCoordinate) -> Bool {
        guard let localCenter else { return route == nil }
        // 가장자리에 닿기 전에 미리 갱신한다.
        let threshold = localRadiusMeters * 0.6
        return KoreaCoordinateConverter.project(coordinate).distance(to: localCenter) > threshold
    }

    func reset() {
        route = nil
        projectedRoutePath = []
        cumulativeDistances = []
        routeSegments = []
        localIndex = nil
        localCenter = nil
        localRadiusMeters = 0
        lastPathIndex = nil
    }

    // MARK: - 조회

    func currentLimitKPH(at coordinate: NaverCoordinate) -> Int? {
        if let segment = currentSegment(at: coordinate) {
            return segment.limitKPH
        }
        return currentMatch(at: coordinate)?.limitKPH
    }

    func currentMatch(at coordinate: NaverCoordinate) -> SpeedLimitMatch? {
        guard let localIndex else { return nil }
        let point = KoreaCoordinateConverter.project(coordinate)
        return localIndex.nearestMatch(to: point,
                                       maxDistanceMeters: matchToleranceMeters,
                                       preferredHeading: routeHeading(near: point))
    }

    /// 현재 위치가 속한 경로 구간.
    func currentSegment(at coordinate: NaverCoordinate) -> RouteSpeedLimitSegment? {
        guard !routeSegments.isEmpty, let pathIndex = nearestRoutePathIndex(to: coordinate) else { return nil }
        return routeSegments.last { $0.startPathIndex <= pathIndex }
    }

    /// 현재 위치 기준, 앞쪽에서 처음 만나는 "제한속도가 바뀌는" 구간.
    ///
    /// 올라가는 경우도 돌려준다. 경고를 띄울지 말지는 현재 속도까지 아는 `alert(at:speedKPH:)` 가 정한다.
    func nextLimitChange(at coordinate: NaverCoordinate,
                         withinMeters: Double? = nil) -> (segment: RouteSpeedLimitSegment, distanceAhead: Double)? {

        guard let pathIndex = nearestRoutePathIndex(to: coordinate),
              cumulativeDistances.indices.contains(pathIndex) else { return nil }

        let travelled = cumulativeDistances[pathIndex]
        let lookahead = withinMeters ?? alertLeadDistanceMeters
        let currentLimit = routeSegments.last { $0.startPathIndex <= pathIndex }?.limitKPH

        for segment in routeSegments where segment.distanceFromStartMeters > travelled {
            let distanceAhead = segment.distanceFromStartMeters - travelled
            if distanceAhead > lookahead { break }
            // 제한속도를 모르는 구간은 "바뀌었다"고 볼 수 없다.
            guard let limit = segment.limitKPH, segment.isReliableLimit else { continue }
            if limit == currentLimit { continue }
            return (segment, distanceAhead)
        }
        return nil
    }

    func alert(at coordinate: NaverCoordinate, speedKPH: Int) -> SpeedLimitAlert? {

        let current = currentLimitContext(at: coordinate)

        // 1) 현재 구간을 넘고 있는가. 초과가 감속 예고보다 급하다.
        if let current, current.isReliable, speedKPH > current.limitKPH + toleranceKPH {
            return SpeedLimitAlert(severity: .exceeding,
                                   limitKPH: current.limitKPH,
                                   roadName: current.roadName,
                                   roadRank: current.roadRank,
                                   distanceAheadMeters: 0,
                                   currentSpeedKPH: speedKPH)
        }

        // 2) 앞쪽에서 감속이 필요한가.
        //    제한속도가 올라가는 구간은 알릴 이유가 없다. 현재 제한속도를 모를 때는
        //    지금 속도 그대로 가면 넘게 되는 경우에만 알린다. (안 그러면 계속 깜빡인다)
        guard let (segment, distanceAhead) = nextLimitChange(at: coordinate),
              let upcomingLimit = segment.limitKPH else { return nil }

        let needsSlowdown = current.map { upcomingLimit < $0.limitKPH }
            ?? (speedKPH > upcomingLimit + toleranceKPH)
        guard needsSlowdown else { return nil }

        return SpeedLimitAlert(severity: .upcoming,
                               limitKPH: upcomingLimit,
                               roadName: segment.roadName,
                               roadRank: segment.roadRank,
                               distanceAheadMeters: Int(distanceAhead.rounded()),
                               currentSpeedKPH: speedKPH)
    }

    // MARK: - 내부

    /// 현재 위치의 제한속도를 경로 구간 → 링크 스냅 순으로 찾는다.
    private func currentLimitContext(at coordinate: NaverCoordinate)
    -> (limitKPH: Int, roadName: String?, roadRank: RoadRank, isReliable: Bool)? {

        if let segment = currentSegment(at: coordinate), let limit = segment.limitKPH {
            return (limit, segment.roadName, segment.roadRank, segment.isReliableLimit)
        }
        if let match = currentMatch(at: coordinate) {
            return (match.limitKPH, match.roadName, match.roadRank, match.link.isReliableLimit)
        }
        return nil
    }

    /// 현재 위치에 가장 가까운 경로 점의 인덱스.
    ///
    /// `DrivingRoute.nearestPathIndex(to:)` 는 매번 경로 전체를 훑는다.
    /// 주행 중에는 위치가 이전 지점 근처에 있으므로 직전 인덱스 주변을 먼저 본다.
    private func nearestRoutePathIndex(to coordinate: NaverCoordinate) -> Int? {
        nearestRouteIndex(to: KoreaCoordinateConverter.project(coordinate))
    }

    private func nearestRouteIndex(to point: UTMKPoint) -> Int? {
        guard !projectedRoutePath.isEmpty else { return nil }

        if let lastPathIndex {
            // 앞뒤 200점 범위를 먼저 본다. 그 안에서 가장자리에 붙으면 전체를 다시 훑는다.
            let window = 200
            let lower = max(0, lastPathIndex - window)
            let upper = min(projectedRoutePath.count - 1, lastPathIndex + window)
            let localBest = bestIndex(in: lower...upper, to: point)
            if localBest > lower, localBest < upper {
                self.lastPathIndex = localBest
                return localBest
            }
        }

        let best = bestIndex(in: 0...(projectedRoutePath.count - 1), to: point)
        lastPathIndex = best
        return best
    }

    private func bestIndex(in range: ClosedRange<Int>, to point: UTMKPoint) -> Int {
        var bestIndex = range.lowerBound
        var bestDistance = Double.greatestFiniteMagnitude
        for index in range {
            let distance = projectedRoutePath[index].squaredDistance(to: point)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// 경로 위 해당 지점의 진행 방위(도). 경로가 없으면 nil.
    private func routeHeading(near point: UTMKPoint) -> Double? {
        guard let index = nearestRouteIndex(to: point) else { return nil }
        return Self.heading(of: projectedRoutePath, at: index)
    }

    // MARK: 구간 만들기

    /// 경로 각 점을 링크에 스냅한 뒤, 제한속도가 같은 연속 구간으로 묶는다.
    private func makeSegments(projectedPath: [UTMKPoint],
                              distances: [Double],
                              index: SpeedLimitLinkIndex) -> [RouteSpeedLimitSegment] {

        guard !projectedPath.isEmpty, !index.isEmpty else { return [] }

        // 1) 점별 매칭.
        var matches: [SpeedLimitMatch?] = []
        matches.reserveCapacity(projectedPath.count)
        for (pointIndex, point) in projectedPath.enumerated() {
            let heading = Self.heading(of: projectedPath, at: pointIndex)
            matches.append(index.nearestMatch(to: point,
                                              maxDistanceMeters: matchToleranceMeters,
                                              preferredHeading: heading))
        }

        // 2) 제한속도가 같은 연속 구간으로 묶는다.
        var runs: [(start: Int, end: Int)] = []
        var runStart = 0
        for pointIndex in 1..<projectedPath.count where
            matches[pointIndex - 1]?.limitKPH != matches[pointIndex]?.limitKPH {
            runs.append((runStart, pointIndex - 1))
            runStart = pointIndex
        }
        runs.append((runStart, projectedPath.count - 1))

        // 구간이 경로를 빈틈없이 덮도록, 한 구간의 끝은 다음 구간이 시작하는 지점으로 잡는다.
        // (마지막 점까지의 거리로 끊으면 구간 사이에 경로 점 간격만큼 구멍이 생긴다)
        let segments: [RouteSpeedLimitSegment] = runs.map { run in
            let match = matches[run.start]
            let startDistance = distances[run.start]
            let endDistance = distances[min(run.end + 1, distances.count - 1)]
            return RouteSpeedLimitSegment(
                startPathIndex: run.start,
                endPathIndex: run.end,
                limitKPH: match?.limitKPH,
                roadName: match?.roadName,
                roadRank: match?.roadRank ?? .unknown,
                distanceFromStartMeters: startDistance,
                lengthMeters: max(0, endDistance - startDistance),
                representativeLinkID: match?.link.linkID
            )
        }

        return mergeShortSegments(segments)
    }

    /// 너무 짧은 구간을 앞 구간에 흡수시킨다.
    ///
    /// 교차로나 램프에서 링크가 잘게 끊겨 5m 짜리 구간이 생기면 안내가 깜빡인다.
    private func mergeShortSegments(_ segments: [RouteSpeedLimitSegment]) -> [RouteSpeedLimitSegment] {
        guard segments.count > 1 else { return segments }

        var merged: [RouteSpeedLimitSegment] = []
        for segment in segments {
            guard var previous = merged.last else {
                merged.append(segment)
                continue
            }

            if segment.lengthMeters < minimumSegmentLengthMeters {
                // 짧은 구간은 앞 구간을 늘려서 삼킨다.
                previous.endPathIndex = segment.endPathIndex
                previous.lengthMeters = segment.endDistanceFromStartMeters - previous.distanceFromStartMeters
                merged[merged.count - 1] = previous
            } else if previous.limitKPH == segment.limitKPH {
                // 흡수 과정에서 같은 제한속도가 이웃하게 되면 합친다.
                previous.endPathIndex = segment.endPathIndex
                previous.lengthMeters = segment.endDistanceFromStartMeters - previous.distanceFromStartMeters
                merged[merged.count - 1] = previous
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    // MARK: 계산 도우미

    /// 경로 각 점까지의 누적 거리(m).
    private static func cumulativeDistances(of path: [UTMKPoint]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(path.count)
        var total = 0.0
        for (index, point) in path.enumerated() {
            if index > 0 { total += point.distance(to: path[index - 1]) }
            result.append(total)
        }
        return result
    }

    /// 경로 위 특정 점에서의 진행 방위(도).
    private static func heading(of path: [UTMKPoint], at index: Int) -> Double? {
        guard path.count >= 2 else { return nil }
        let start = max(0, min(index, path.count - 2))
        let delta = path[start + 1] - path[start]
        guard delta.length > 0 else { return nil }
        let degrees = atan2(delta.x, delta.y) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

//
//  RouteProgressIndex.swift
//  DriveInGyeongbuk
//
//  "이 좌표는 경로의 몇 번째 점쯤인가"를 빠르게 답한다.
//
//  왜 필요한가
//    제한속도 구간(`RouteSpeedLimitSegment`)은 위치를 **경로 인덱스**로 갖고 있다.
//    주행 샘플과 구간을 맞추려면 샘플마다 경로 인덱스를 구해야 하는데,
//    `DrivingRoute.nearestPathIndex(to:)` 는 매번 경로 전체를 훑는다.
//    샘플 수백 개 × 경로 점 수천 개면 그것만으로 체감이 될 만큼 느려진다.
//
//  어떻게 빠른가
//    주행 샘플은 경로를 따라 **앞으로만** 간다. 그래서 직전에 찾은 인덱스부터
//    앞쪽으로만 훑으면 전체 비용이 (샘플 수 + 경로 점 수) 로 떨어진다.
//    경로를 이탈했거나 되돌아간 경우를 대비해 전체 탐색으로 물러설 길도 남겨 뒀다.
//
//  좌표 비교는 `SpeedLimitService` 와 같은 평면 좌표(UTM-K)에서 한다.
//  위경도 그대로 빼면 위도에 따라 거리가 왜곡된다.
//

import Foundation

nonisolated final class RouteProgressIndex {

    private let projectedPath: [UTMKPoint]
    /// 경로 출발점에서 각 점까지의 누적 거리(m).
    private let cumulativeDistances: [Double]
    /// 직전 조회 결과. 다음 조회의 시작점이 된다.
    private var cursor = 0

    init(path: [NaverCoordinate]) {
        projectedPath = path.map(KoreaCoordinateConverter.project)
        var distances: [Double] = []
        distances.reserveCapacity(projectedPath.count)
        var total = 0.0
        for (index, point) in projectedPath.enumerated() {
            if index > 0 { total += point.distance(to: projectedPath[index - 1]) }
            distances.append(total)
        }
        cumulativeDistances = distances
    }

    var isEmpty: Bool { projectedPath.isEmpty }

    /// 경로 총 길이(m).
    var totalDistanceMeters: Double { cumulativeDistances.last ?? 0 }

    /// 좌표에 가장 가까운 경로 점의 인덱스.
    ///
    /// 시간순으로 부르면 앞으로만 훑어 빠르다. 순서를 섞어 부르면 정확도는 같고 느려진다.
    func index(for coordinate: NaverCoordinate) -> Int? {
        guard !projectedPath.isEmpty else { return nil }
        let point = KoreaCoordinateConverter.project(coordinate)

        // 커서부터 앞쪽 창을 먼저 본다.
        let window = 400
        let upper = min(projectedPath.count - 1, cursor + window)
        let localBest = bestIndex(in: cursor...upper, to: point)

        // 창 끝에 붙었으면 더 멀리 갔다는 뜻이라 전체를 다시 훑는다.
        if localBest >= upper, upper < projectedPath.count - 1 {
            let best = bestIndex(in: 0...(projectedPath.count - 1), to: point)
            cursor = best
            return best
        }

        cursor = localBest
        return localBest
    }

    /// 출발점에서 이 좌표까지 진행한 거리(m).
    func distanceFromStart(for coordinate: NaverCoordinate) -> Double? {
        index(for: coordinate).flatMap(distanceFromStart(atIndex:))
    }

    /// 출발점에서 경로 `index` 번째 점까지의 거리(m).
    /// `index(for:)` 로 이미 인덱스를 구했다면 탐색을 두 번 하지 않도록 이쪽을 쓴다.
    func distanceFromStart(atIndex index: Int) -> Double? {
        cumulativeDistances.indices.contains(index) ? cumulativeDistances[index] : nil
    }

    /// 커서를 처음으로 되돌린다. 같은 기록을 다시 훑을 때 부른다.
    func rewind() {
        cursor = 0
    }

    private func bestIndex(in range: ClosedRange<Int>, to point: UTMKPoint) -> Int {
        var bestIndex = range.lowerBound
        var bestDistance = Double.greatestFiniteMagnitude
        for index in range {
            let distance = projectedPath[index].squaredDistance(to: point)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}

//
//  KoreaCoordinateConverter.swift
//  DriveInGyeongbuk
//
//  WGS84(위경도) ↔ EPSG:5179(Korea 2000 / Unified CS, "UTM-K") 좌표 변환.
//
//  왜 필요한가
//    번들에 들어 있는 제한속도 데이터셋(`gyeongbuk_speed_limits.sqlite`)의 링크 형상은
//    EPSG:5179 평면 좌표(미터)로 저장되어 있다. 반면 앱이 다루는 좌표(`NaverCoordinate`)는
//    WGS84 위경도다. 두 좌표계를 오가는 변환이 이 파일 한 곳에만 있어야 실수가 없다.
//
//  왜 평면 좌표에서 매칭하는가
//    "현재 위치가 어느 도로 링크 위에 있는가"는 점-선분 최단거리 문제다.
//    위경도에서 직접 풀면 위도에 따라 경도 1도의 실제 거리가 달라져 보정이 필요하지만,
//    EPSG:5179 는 이미 미터 단위 평면이라 그냥 유클리드 거리로 풀 수 있다.
//    경상북도 범위(중앙자오선 127.5°E 에서 최대 약 300km)에서 축척 왜곡은 0.1% 미만이다.
//
//  투영 파라미터 (EPSG:5179)
//    타원체 GRS80 · 횡축 메르카토르 · 원점 위도 38°N · 중앙자오선 127.5°E
//    축척계수 0.9996 · 가산 동거리(false easting) 1,000,000m · 가산 북거리 2,000,000m
//
//  GRS80 과 WGS84 의 편평률 차이는 1mm 미만이고, Korea 2000 은 ITRF2000 기반이라
//  내비게이션 용도에서는 측지계 변환(datum shift) 없이 같은 타원체로 취급해도 무방하다.
//

import Foundation

/// EPSG:5179 평면 좌표 한 점. 단위는 **미터**.
nonisolated struct UTMKPoint: Hashable {
    /// 동거리(easting).
    var x: Double
    /// 북거리(northing).
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// 다른 점까지의 평면 거리(m).
    func distance(to other: UTMKPoint) -> Double {
        (self - other).length
    }

    /// 제곱 거리. 최근접 탐색에서 제곱근 계산을 피하려고 쓴다.
    func squaredDistance(to other: UTMKPoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }

    var length: Double { (x * x + y * y).squareRoot() }

    static func - (lhs: UTMKPoint, rhs: UTMKPoint) -> UTMKPoint {
        UTMKPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func + (lhs: UTMKPoint, rhs: UTMKPoint) -> UTMKPoint {
        UTMKPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func * (lhs: UTMKPoint, rhs: Double) -> UTMKPoint {
        UTMKPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

/// EPSG:5179 평면 상의 사각 영역(미터).
nonisolated struct UTMKBounds: Hashable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double

    init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    /// 점들을 모두 감싸는 최소 사각형. 비어 있으면 nil.
    init?(points: [UTMKPoint]) {
        guard let first = points.first else { return nil }
        var bounds = UTMKBounds(minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        for point in points.dropFirst() {
            bounds.minX = min(bounds.minX, point.x)
            bounds.maxX = max(bounds.maxX, point.x)
            bounds.minY = min(bounds.minY, point.y)
            bounds.maxY = max(bounds.maxY, point.y)
        }
        self = bounds
    }

    /// 사방으로 `meters` 만큼 넓힌 영역.
    func expanded(by meters: Double) -> UTMKBounds {
        UTMKBounds(minX: minX - meters, maxX: maxX + meters,
                   minY: minY - meters, maxY: maxY + meters)
    }

    func intersects(_ other: UTMKBounds) -> Bool {
        maxX >= other.minX && minX <= other.maxX && maxY >= other.minY && minY <= other.maxY
    }

    func contains(_ point: UTMKPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

// MARK: -

/// WGS84 ↔ EPSG:5179 변환기.
///
/// 상태가 없는 순수 계산이라 어느 스레드에서 불러도 안전하다.
nonisolated enum KoreaCoordinateConverter {

    // MARK: 투영 상수 (GRS80 / EPSG:5179)

    /// GRS80 장반경(m).
    private static let a = 6_378_137.0
    /// GRS80 편평률의 역수.
    private static let inverseFlattening = 298.257222101
    private static let f = 1 / inverseFlattening
    /// 제1이심률의 제곱.
    private static let e2 = f * (2 - f)
    /// 제2이심률의 제곱.
    private static let ep2 = e2 / (1 - e2)

    /// 원점 위도(rad). 38°N
    private static let originLatitude = 38.0 * .pi / 180
    /// 중앙자오선(rad). 127.5°E
    private static let centralMeridian = 127.5 * .pi / 180
    /// 축척계수.
    private static let k0 = 0.9996
    /// 가산 동거리(m).
    private static let falseEasting = 1_000_000.0
    /// 가산 북거리(m).
    private static let falseNorthing = 2_000_000.0

    /// 원점 위도까지의 자오선호 길이. 매번 계산할 필요가 없어 미리 구해 둔다.
    private static let meridianArcAtOrigin = meridianArc(originLatitude)

    /// 데이터셋이 담고 있는 영역(EPSG:5179). `metadata.bounds_epsg5179` 값이다.
    /// 경상북도 본토 + 울릉도·독도를 포함한다.
    static let datasetBounds = UTMKBounds(minX: 1_026_145.88, maxX: 1_301_919.09,
                                          minY: 1_730_244.23, maxY: 1_955_417.79)

    // MARK: 변환

    /// 위경도 → EPSG:5179 평면 좌표.
    static func project(_ coordinate: NaverCoordinate) -> UTMKPoint {
        project(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func project(latitude: Double, longitude: Double) -> UTMKPoint {
        let phi = latitude * .pi / 180
        let lambda = longitude * .pi / 180

        let sinPhi = sin(phi)
        let cosPhi = cos(phi)
        let tanPhi = tan(phi)

        // 묘유선 곡률반경.
        let n = a / (1 - e2 * sinPhi * sinPhi).squareRoot()
        let t = tanPhi * tanPhi
        let c = ep2 * cosPhi * cosPhi
        let aTerm = (lambda - centralMeridian) * cosPhi

        let a2 = aTerm * aTerm
        let a3 = a2 * aTerm
        let a4 = a3 * aTerm
        let a5 = a4 * aTerm
        let a6 = a5 * aTerm

        let x = falseEasting + k0 * n * (
            aTerm
            + (1 - t + c) * a3 / 6
            + (5 - 18 * t + t * t + 72 * c - 58 * ep2) * a5 / 120
        )

        let y = falseNorthing + k0 * (
            meridianArc(phi) - meridianArcAtOrigin
            + n * tanPhi * (
                a2 / 2
                + (5 - t + 9 * c + 4 * c * c) * a4 / 24
                + (61 - 58 * t + t * t + 600 * c - 330 * ep2) * a6 / 720
            )
        )

        return UTMKPoint(x: x, y: y)
    }

    /// EPSG:5179 평면 좌표 → 위경도.
    static func unproject(_ point: UTMKPoint) -> NaverCoordinate {
        let x = point.x - falseEasting
        let y = point.y - falseNorthing

        let m = meridianArcAtOrigin + y / k0
        let e1 = (1 - (1 - e2).squareRoot()) / (1 + (1 - e2).squareRoot())
        let mu = m / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 * e2 * e2 / 256))

        // 등거리 위도(footprint latitude).
        let e1_2 = e1 * e1
        let e1_3 = e1_2 * e1
        let e1_4 = e1_3 * e1
        let phi1 = mu
            + (3 * e1 / 2 - 27 * e1_3 / 32) * sin(2 * mu)
            + (21 * e1_2 / 16 - 55 * e1_4 / 32) * sin(4 * mu)
            + (151 * e1_3 / 96) * sin(6 * mu)
            + (1097 * e1_4 / 512) * sin(8 * mu)

        let sinPhi1 = sin(phi1)
        let cosPhi1 = cos(phi1)
        let tanPhi1 = tan(phi1)

        let c1 = ep2 * cosPhi1 * cosPhi1
        let t1 = tanPhi1 * tanPhi1
        let n1 = a / (1 - e2 * sinPhi1 * sinPhi1).squareRoot()
        let r1 = a * (1 - e2) / pow(1 - e2 * sinPhi1 * sinPhi1, 1.5)
        let d = x / (n1 * k0)

        let d2 = d * d
        let d3 = d2 * d
        let d4 = d3 * d
        let d5 = d4 * d
        let d6 = d5 * d

        let phi = phi1 - (n1 * tanPhi1 / r1) * (
            d2 / 2
            - (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * ep2) * d4 / 24
            + (61 + 90 * t1 + 298 * c1 + 45 * t1 * t1 - 252 * ep2 - 3 * c1 * c1) * d6 / 720
        )

        let lambda = centralMeridian + (
            d
            - (1 + 2 * t1 + c1) * d3 / 6
            + (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * ep2 + 24 * t1 * t1) * d5 / 120
        ) / cosPhi1

        return NaverCoordinate(latitude: phi * 180 / .pi, longitude: lambda * 180 / .pi)
    }

    /// 위경도 사각 영역 → 평면 사각 영역.
    ///
    /// 투영은 직선을 완전히 보존하지 않으므로 네 꼭짓점을 모두 변환해 감싸는 사각형을 만든다.
    static func project(_ bounds: NaverCoordinateBounds) -> UTMKBounds {
        let corners = [
            project(latitude: bounds.southWest.latitude, longitude: bounds.southWest.longitude),
            project(latitude: bounds.southWest.latitude, longitude: bounds.northEast.longitude),
            project(latitude: bounds.northEast.latitude, longitude: bounds.southWest.longitude),
            project(latitude: bounds.northEast.latitude, longitude: bounds.northEast.longitude)
        ]
        // 꼭짓점이 4개이므로 항상 성공한다.
        return UTMKBounds(points: corners) ?? datasetBounds
    }

    /// 평면 사각 영역 → 위경도 사각 영역.
    static func unproject(_ bounds: UTMKBounds) -> NaverCoordinateBounds {
        let corners = [
            unproject(UTMKPoint(x: bounds.minX, y: bounds.minY)),
            unproject(UTMKPoint(x: bounds.maxX, y: bounds.minY)),
            unproject(UTMKPoint(x: bounds.minX, y: bounds.maxY)),
            unproject(UTMKPoint(x: bounds.maxX, y: bounds.maxY))
        ]
        let latitudes = corners.map(\.latitude)
        let longitudes = corners.map(\.longitude)
        return NaverCoordinateBounds(
            southWest: NaverCoordinate(latitude: latitudes.min() ?? 0, longitude: longitudes.min() ?? 0),
            northEast: NaverCoordinate(latitude: latitudes.max() ?? 0, longitude: longitudes.max() ?? 0)
        )
    }

    /// 데이터셋이 커버하는 영역(경상북도) 안인지.
    /// 밖이라면 조회해 봐야 결과가 없으므로 미리 걸러 낼 때 쓴다.
    static func isInsideDataset(_ coordinate: NaverCoordinate) -> Bool {
        datasetBounds.contains(project(coordinate))
    }

    // MARK: 내부

    /// 적도에서 위도 `phi` 까지의 자오선호 길이(m).
    private static func meridianArc(_ phi: Double) -> Double {
        let e4 = e2 * e2
        let e6 = e4 * e2

        let c0 = 1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256
        let c2 = 3.0 / 8 * (e2 + e4 / 4 + 15 * e6 / 128)
        let c4 = 15.0 / 256 * (e4 + 3 * e6 / 4)
        let c6 = 35.0 / 3072 * e6

        return a * (c0 * phi - c2 * sin(2 * phi) + c4 * sin(4 * phi) - c6 * sin(6 * phi))
    }
}

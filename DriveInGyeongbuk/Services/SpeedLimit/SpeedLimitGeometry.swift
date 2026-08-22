//
//  SpeedLimitGeometry.swift
//  DriveInGyeongbuk
//
//  제한속도 데이터셋의 형상(BLOB) 해석과, 위치 매칭에 쓰는 기하 계산.
//
//  구성
//    1. GSL1GeometryDecoder : `links.geometry` 컬럼의 커스텀 바이너리 포맷 파서
//    2. PolylineMath        : 점-폴리라인 최단거리 (평면 좌표 기준)
//    3. SpeedLimitLinkIndex : 링크 묶음에 대한 균등 격자 공간 인덱스
//

import Foundation

// MARK: - GSL1 형상 파서

/// `links.geometry` 컬럼에 들어 있는 GSL1 바이너리를 좌표열로 푼다.
///
/// 포맷 명세는 DB 의 `metadata` 테이블 `geometry_format` 키에 문자열로 박혀 있다.
/// 전부 리틀엔디언이다.
///
/// ```
/// offset  size            내용
/// 0       4               매직 "GSL1"
/// 4       1               버전 (현재 1)
/// 5       1               플래그 (현재 0)
/// 6       2  uint16       파트 수
/// 8       4  uint32       전체 점 개수
/// 12      4 * 파트 수      파트별 점 개수 (uint32)
/// …       8 * 점 개수      점 (int32 x_cm, int32 y_cm) — EPSG:5179 절대좌표, 센티미터
/// ```
nonisolated enum GSL1GeometryDecoder {

    /// 매직 넘버 "GSL1".
    private static let magic: [UInt8] = [0x47, 0x53, 0x4C, 0x31]
    private static let headerSize = 12
    private static let bytesPerPoint = 8
    /// 저장 단위가 센티미터라 미터로 바꾸는 계수.
    private static let centimetreToMetre = 0.01

    /// 형상 BLOB 을 파트별 좌표열로 푼다.
    ///
    /// 현재 데이터셋은 `metadata.multipart_link_count = 0` 이라 파트가 항상 1개지만,
    /// 포맷 자체는 멀티파트를 허용하므로 그대로 해석한다.
    static func decodeParts(_ data: Data, linkID: Int64) throws -> [[UTMKPoint]] {
        guard data.count >= headerSize else {
            throw SpeedLimitError.malformedGeometry(linkID: linkID, reason: "헤더가 잘립니다(\(data.count)바이트)")
        }

        // Data 의 인덱스는 0부터 시작한다는 보장이 없어 Array 로 복사해 다룬다.
        let bytes = [UInt8](data)

        guard Array(bytes[0..<4]) == magic else {
            throw SpeedLimitError.malformedGeometry(linkID: linkID, reason: "매직 넘버 불일치")
        }
        let version = bytes[4]
        guard version == 1 else {
            throw SpeedLimitError.malformedGeometry(linkID: linkID, reason: "알 수 없는 버전 \(version)")
        }

        let partCount = Int(readUInt16(bytes, at: 6))
        let pointCount = Int(readUInt32(bytes, at: 8))
        guard partCount > 0, pointCount > 0 else {
            throw SpeedLimitError.malformedGeometry(linkID: linkID, reason: "빈 형상")
        }

        let partTableSize = partCount * 4
        let expectedSize = headerSize + partTableSize + pointCount * bytesPerPoint
        guard bytes.count >= expectedSize else {
            throw SpeedLimitError.malformedGeometry(
                linkID: linkID,
                reason: "길이 부족 (기대 \(expectedSize), 실제 \(bytes.count))"
            )
        }

        var partSizes: [Int] = []
        partSizes.reserveCapacity(partCount)
        for index in 0..<partCount {
            partSizes.append(Int(readUInt32(bytes, at: headerSize + index * 4)))
        }
        guard partSizes.reduce(0, +) == pointCount else {
            throw SpeedLimitError.malformedGeometry(linkID: linkID, reason: "파트별 점 개수 합이 전체와 다릅니다")
        }

        var offset = headerSize + partTableSize
        var parts: [[UTMKPoint]] = []
        parts.reserveCapacity(partCount)

        for size in partSizes {
            var points: [UTMKPoint] = []
            points.reserveCapacity(size)
            for _ in 0..<size {
                let x = Double(readInt32(bytes, at: offset)) * centimetreToMetre
                let y = Double(readInt32(bytes, at: offset + 4)) * centimetreToMetre
                points.append(UTMKPoint(x: x, y: y))
                offset += bytesPerPoint
            }
            parts.append(points)
        }

        return parts
    }

    /// 링크 하나의 대표 형상. 멀티파트면 가장 긴 파트를 쓴다.
    static func decodePath(_ data: Data, linkID: Int64) throws -> [UTMKPoint] {
        let parts = try decodeParts(data, linkID: linkID)
        guard let longest = parts.max(by: { $0.count < $1.count }), longest.count >= 2 else {
            throw SpeedLimitError.malformedGeometry(linkID: linkID, reason: "점이 2개 미만입니다")
        }
        return longest
    }

    // MARK: 리틀엔디언 읽기

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readInt32(_ bytes: [UInt8], at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(bytes, at: offset))
    }
}

// MARK: - 폴리라인 기하

/// 평면 좌표(EPSG:5179, 미터) 기준 폴리라인 계산.
nonisolated enum PolylineMath {

    /// 폴리라인 전체 길이(m).
    static func length(of path: [UTMKPoint]) -> Double {
        guard path.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<path.count {
            total += path[index].distance(to: path[index - 1])
        }
        return total
    }

    /// 점에서 폴리라인까지의 최단거리와 그 지점.
    ///
    /// - Returns: 수선의 발 좌표, 수직 거리(m), 폴리라인 시작점에서 그 지점까지의 거리(m).
    ///            폴리라인이 비어 있으면 nil.
    static func nearestPoint(on path: [UTMKPoint],
                             to point: UTMKPoint) -> (snapped: UTMKPoint, distance: Double, progressMeters: Double)? {
        guard let first = path.first else { return nil }
        guard path.count >= 2 else {
            return (first, first.distance(to: point), 0)
        }

        var bestSnapped = first
        var bestSquaredDistance = Double.greatestFiniteMagnitude
        var bestProgress = 0.0
        var travelled = 0.0

        for index in 1..<path.count {
            let start = path[index - 1]
            let end = path[index]
            let segment = end - start
            let segmentLengthSquared = segment.x * segment.x + segment.y * segment.y

            // 길이가 0인 선분(중복 점)은 시작점으로 취급한다.
            var t = 0.0
            if segmentLengthSquared > 0 {
                let toPoint = point - start
                t = (toPoint.x * segment.x + toPoint.y * segment.y) / segmentLengthSquared
                t = min(max(t, 0), 1)
            }

            let snapped = start + segment * t
            let squaredDistance = snapped.squaredDistance(to: point)
            if squaredDistance < bestSquaredDistance {
                bestSquaredDistance = squaredDistance
                bestSnapped = snapped
                bestProgress = travelled + segmentLengthSquared.squareRoot() * t
            }

            travelled += segmentLengthSquared.squareRoot()
        }

        return (bestSnapped, bestSquaredDistance.squareRoot(), bestProgress)
    }

    /// 폴리라인의 진행 방향(도, 정북 0° 시계방향)을 구한다.
    ///
    /// 같은 도로의 상·하행 링크를 구분할 때 쓴다. 점이 2개 미만이면 nil.
    static func heading(of path: [UTMKPoint], atProgressMeters progress: Double) -> Double? {
        guard path.count >= 2 else { return nil }

        var travelled = 0.0
        for index in 1..<path.count {
            let segmentLength = path[index].distance(to: path[index - 1])
            if travelled + segmentLength >= progress || index == path.count - 1 {
                let delta = path[index] - path[index - 1]
                guard delta.length > 0 else { continue }
                let degrees = atan2(delta.x, delta.y) * 180 / .pi
                return degrees < 0 ? degrees + 360 : degrees
            }
            travelled += segmentLength
        }
        return nil
    }

    /// 두 방위각의 차이(0~180도).
    static func headingDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let diff = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }
}

// MARK: - 공간 인덱스

/// 링크 묶음에 대한 균등 격자 인덱스.
///
/// 왜 필요한가
///   경로 전체(수천 개 점)를 수천 개 링크와 매칭하면 단순 반복은 수천만 번 계산이 된다.
///   링크를 200m 격자에 미리 담아 두면 한 점당 후보가 보통 수십 개로 줄어든다.
nonisolated struct SpeedLimitLinkIndex {

    /// 격자 한 칸의 크기(m).
    private let cellSize: Double
    /// 격자 좌표 → 해당 칸에 걸치는 링크의 인덱스 목록.
    private var cells: [Cell: [Int]] = [:]

    let links: [SpeedLimitLink]

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    init(links: [SpeedLimitLink], cellSize: Double = 200) {
        self.links = links
        self.cellSize = cellSize

        for (index, link) in links.enumerated() {
            let bounds = link.projectedBounds
            let minCellX = Int(floor(bounds.minX / cellSize))
            let maxCellX = Int(floor(bounds.maxX / cellSize))
            let minCellY = Int(floor(bounds.minY / cellSize))
            let maxCellY = Int(floor(bounds.maxY / cellSize))

            // 아주 긴 링크(고속도로 등)가 격자를 과도하게 차지하지 않도록 상한을 둔다.
            guard (maxCellX - minCellX + 1) * (maxCellY - minCellY + 1) <= 4096 else {
                overlongLinkIndices.append(index)
                continue
            }

            for cellX in minCellX...maxCellX {
                for cellY in minCellY...maxCellY {
                    cells[Cell(x: cellX, y: cellY), default: []].append(index)
                }
            }
        }
    }

    /// 격자에 담기엔 너무 긴 링크. 매번 전수 검사한다(개수가 매우 적다).
    private var overlongLinkIndices: [Int] = []

    var isEmpty: Bool { links.isEmpty }

    /// 좌표에서 가장 가까운 링크를 찾는다.
    /// - Parameters:
    ///   - point: EPSG:5179 평면 좌표.
    ///   - maxDistanceMeters: 이 거리보다 멀면 매칭 실패로 본다.
    ///   - preferredHeading: 알고 있다면 진행 방위(도). 같은 도로의 반대편 링크를 걸러 낸다.
    func nearestMatch(to point: UTMKPoint,
                      maxDistanceMeters: Double,
                      preferredHeading: Double? = nil) -> SpeedLimitMatch? {

        var candidates = Set<Int>()
        let radiusInCells = max(1, Int(ceil(maxDistanceMeters / cellSize)))
        let centerX = Int(floor(point.x / cellSize))
        let centerY = Int(floor(point.y / cellSize))

        for offsetX in -radiusInCells...radiusInCells {
            for offsetY in -radiusInCells...radiusInCells {
                if let bucket = cells[Cell(x: centerX + offsetX, y: centerY + offsetY)] {
                    candidates.formUnion(bucket)
                }
            }
        }
        candidates.formUnion(overlongLinkIndices)
        guard !candidates.isEmpty else { return nil }

        var best: SpeedLimitMatch?
        var bestScore = Double.greatestFiniteMagnitude

        for index in candidates {
            let link = links[index]
            guard link.projectedBounds.expanded(by: maxDistanceMeters).contains(point) else { continue }
            guard let nearest = link.nearestPoint(to: point), nearest.distance <= maxDistanceMeters else { continue }

            // 진행 방향이 어긋난 링크(반대 차선·교차 도로)에는 가중치를 준다.
            var score = nearest.distance
            if let preferredHeading,
               let linkHeading = PolylineMath.heading(of: link.projectedPath,
                                                      atProgressMeters: nearest.progressMeters) {
                let difference = PolylineMath.headingDifference(preferredHeading, linkHeading)
                score += difference * 0.5
            }

            guard score < bestScore else { continue }
            bestScore = score
            best = SpeedLimitMatch(
                link: link,
                snappedCoordinate: KoreaCoordinateConverter.unproject(nearest.snapped),
                lateralDistanceMeters: nearest.distance,
                progressMeters: nearest.progressMeters
            )
        }

        return best
    }
}

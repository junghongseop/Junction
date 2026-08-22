//
//  SpeedLimitDataSource.swift
//  DriveInGyeongbuk
//
//  제한속도 원천 데이터 공급자.
//
//  현재 소스
//    번들 내장 SQLite (`gyeongbuk_speed_limits.sqlite`, 국가표준노드링크 기반).
//    오프라인에서 동작하고 네트워크 지연이 없어 주행 중 안내에 적합하다.
//
//  나중에 붙일 소스 (같은 프로토콜로 갈아끼우거나 합치면 된다)
//    - 공공데이터포털 : 전국 무인교통단속카메라 표준 데이터 (고정식·구간단속)
//    - 국가교통정보센터(ITS) : 실시간 가변 제한속도
//    - 보호구역 표준 데이터 : 어린이·노인 보호구역
//
//  스레드
//    이 프로젝트는 기본 액터 격리가 MainActor 라서, 아무 표시도 없는 타입은 MainActor 에 묶인다.
//    SQLite 조회는 메인 스레드에서 하면 안 되므로 프로토콜을 `nonisolated` 로 열어 두고
//    구현체는 `actor` 로 만들었다. 액터가 DB 핸들 접근을 직렬화하는 역할도 겸한다.
//

import Foundation
import SQLite3

/// 제한속도 데이터를 가져오는 방법을 추상화한다.
///
/// 테스트에서는 `InMemorySpeedLimitDataSource` 로 갈아끼울 수 있다.
nonisolated protocol SpeedLimitDataSource: Sendable {

    /// 좌표 주변 반경 안의 도로 링크.
    func links(around coordinate: NaverCoordinate, radiusMeters: Double) async throws -> [SpeedLimitLink]

    /// 폴리라인(경로) 주변 회랑(corridor) 안의 도로 링크. 링크 중복은 제거된다.
    ///
    /// 경로 전체를 한 번에 감싸는 사각형으로 조회하면 경로에서 수십 km 떨어진 링크까지
    /// 딸려 오므로, 구현체는 경로를 잘게 나눠 조회해야 한다.
    func links(alongPath path: [NaverCoordinate], corridorMeters: Double) async throws -> [SpeedLimitLink]
}

extension SpeedLimitDataSource {

    /// 탐색된 경로 주변의 링크를 가져온다.
    func links(along route: DrivingRoute, corridorMeters: Double = 60) async throws -> [SpeedLimitLink] {
        try await links(alongPath: route.path, corridorMeters: corridorMeters)
    }

    /// 좌표 한 곳에 가장 가까운 링크.
    func nearestLink(to coordinate: NaverCoordinate,
                     withinMeters: Double = 40) async throws -> SpeedLimitMatch? {
        let candidates = try await links(around: coordinate, radiusMeters: withinMeters)
        guard !candidates.isEmpty else { return nil }
        return SpeedLimitLinkIndex(links: candidates)
            .nearestMatch(to: KoreaCoordinateConverter.project(coordinate),
                          maxDistanceMeters: withinMeters)
    }
}

// MARK: - 번들 SQLite 구현

/// 번들에 포함된 표준노드링크 제한속도 DB 를 읽는다.
///
/// DB 는 읽기 전용으로 열며, 공간 검색은 `link_index`(R-tree) 를 먼저 태워
/// 후보를 좁힌 뒤 `links` 본체와 조인한다.
actor SQLiteSpeedLimitDataSource: SpeedLimitDataSource {

    /// 번들 리소스 이름.
    static let defaultResourceName = "gyeongbuk_speed_limits"
    static let defaultResourceExtension = "sqlite"

    /// 경로를 잘라 조회할 때 한 조각에 담는 최대 점 개수.
    /// 조각이 너무 크면 사각형이 넓어져 불필요한 링크가 딸려 오고,
    /// 너무 작으면 질의 횟수가 늘어난다.
    private static let pathChunkSize = 32

    private let databaseURL: URL
    private var handle: OpaquePointer?

    /// 같은 링크를 반복 조회하는 일이 잦아(경로 매칭·주행 중 갱신) 파싱 결과를 캐싱한다.
    private var cache: [Int64: SpeedLimitLink] = [:]

    /// - Parameter databaseURL: 직접 지정하지 않으면 앱 번들에서 찾는다.
    init(databaseURL: URL? = nil) throws {
        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            guard let bundled = Bundle.main.url(forResource: Self.defaultResourceName,
                                                withExtension: Self.defaultResourceExtension) else {
                throw SpeedLimitError.databaseNotFound(
                    "\(Self.defaultResourceName).\(Self.defaultResourceExtension)"
                )
            }
            self.databaseURL = bundled
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    // MARK: 조회

    func links(around coordinate: NaverCoordinate, radiusMeters: Double) async throws -> [SpeedLimitLink] {
        let center = KoreaCoordinateConverter.project(coordinate)
        let bounds = UTMKBounds(minX: center.x - radiusMeters, maxX: center.x + radiusMeters,
                                minY: center.y - radiusMeters, maxY: center.y + radiusMeters)
        return try links(in: bounds)
    }

    func links(alongPath path: [NaverCoordinate], corridorMeters: Double) async throws -> [SpeedLimitLink] {
        guard !path.isEmpty else { return [] }

        let projected = path.map(KoreaCoordinateConverter.project)
        var collected: [Int64: SpeedLimitLink] = [:]

        // 경로를 조각내어 조각별 사각형으로 조회한다.
        var index = 0
        while index < projected.count {
            let end = min(index + Self.pathChunkSize, projected.count)
            // 조각 사이가 끊기지 않도록 한 점씩 겹친다.
            let chunk = Array(projected[index..<end])
            if let chunkBounds = UTMKBounds(points: chunk)?.expanded(by: corridorMeters) {
                for link in try links(in: chunkBounds) {
                    collected[link.linkID] = link
                }
            }
            if end == projected.count { break }
            index = end - 1
        }

        return Array(collected.values)
    }

    /// 평면 사각 영역 안(또는 걸치는) 링크를 조회한다.
    private func links(in bounds: UTMKBounds) throws -> [SpeedLimitLink] {
        // 경상북도 밖이면 R-tree 를 타 봐야 결과가 없다.
        guard bounds.intersects(KoreaCoordinateConverter.datasetBounds) else { return [] }

        let database = try openedDatabase()

        // R-tree 에서 후보를 좁힌 뒤 본체와 조인한다.
        let sql = """
        SELECT l.link_id, l.speed_kph, l.road_name, l.road_rank, l.f_node, l.t_node, l.geometry
        FROM link_index AS i
        JOIN links AS l ON l.link_id = i.link_id
        WHERE i.max_x >= ?1 AND i.min_x <= ?2 AND i.max_y >= ?3 AND i.min_y <= ?4
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SpeedLimitError.database(lastErrorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, bounds.minX)
        sqlite3_bind_double(statement, 2, bounds.maxX)
        sqlite3_bind_double(statement, 3, bounds.minY)
        sqlite3_bind_double(statement, 4, bounds.maxY)

        var results: [SpeedLimitLink] = []

        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw SpeedLimitError.database(lastErrorMessage(database))
            }

            let linkID = sqlite3_column_int64(statement, 0)

            // 이미 파싱해 둔 링크면 형상 파싱을 건너뛴다.
            if let cached = cache[linkID] {
                results.append(cached)
                continue
            }

            guard let link = try makeLink(from: statement, linkID: linkID) else { continue }
            cache[linkID] = link
            results.append(link)
        }

        return results
    }

    // MARK: 매핑

    /// 현재 행을 도메인 모델로 만든다. 형상이 깨진 링크는 건너뛴다(nil).
    private func makeLink(from statement: OpaquePointer?, linkID: Int64) throws -> SpeedLimitLink? {
        let speedKPH = Int(sqlite3_column_int(statement, 1))
        let roadName = columnText(statement, index: 2)
        let roadRank = RoadRank(code: columnText(statement, index: 3))
        let fromNode = sqlite3_column_int64(statement, 4)
        let toNode = sqlite3_column_int64(statement, 5)

        guard let blob = sqlite3_column_blob(statement, 6) else { return nil }
        let blobSize = Int(sqlite3_column_bytes(statement, 6))
        guard blobSize > 0 else { return nil }
        let geometry = Data(bytes: blob, count: blobSize)

        // 링크 하나가 깨졌다고 조회 전체를 실패시키지는 않는다.
        guard let projectedPath = try? GSL1GeometryDecoder.decodePath(geometry, linkID: linkID),
              let projectedBounds = UTMKBounds(points: projectedPath) else {
            return nil
        }

        return SpeedLimitLink(
            linkID: linkID,
            limitKPH: speedKPH,
            roadName: roadName,
            roadRank: roadRank,
            fromNodeID: fromNode,
            toNodeID: toNode,
            path: projectedPath.map(KoreaCoordinateConverter.unproject),
            projectedPath: projectedPath,
            lengthMeters: PolylineMath.length(of: projectedPath),
            projectedBounds: projectedBounds
        )
    }

    // MARK: SQLite

    /// 열려 있는 DB 핸들. 처음 부를 때 연다.
    private func openedDatabase() throws -> OpaquePointer {
        if let handle { return handle }

        var database: OpaquePointer?
        // 번들 리소스는 수정할 수 없으므로 읽기 전용으로 연다.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database else {
            let reason = database.map(lastErrorMessage) ?? "열기 실패"
            if let database { sqlite3_close(database) }
            throw SpeedLimitError.database(reason)
        }

        handle = database
        return database
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        let text = String(cString: raw)
        return text.isEmpty ? nil : text
    }

    private func lastErrorMessage(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }
}

// MARK: - 테스트용 구현

/// 미리 만들어 둔 링크 배열만 돌려준다. 단위 테스트/프리뷰에서 DB 없이 쓰려고 둔다.
nonisolated struct InMemorySpeedLimitDataSource: SpeedLimitDataSource {

    var links: [SpeedLimitLink]

    init(links: [SpeedLimitLink] = []) {
        self.links = links
    }

    func links(around coordinate: NaverCoordinate, radiusMeters: Double) async throws -> [SpeedLimitLink] {
        let center = KoreaCoordinateConverter.project(coordinate)
        let bounds = UTMKBounds(minX: center.x - radiusMeters, maxX: center.x + radiusMeters,
                                minY: center.y - radiusMeters, maxY: center.y + radiusMeters)
        return links.filter { $0.projectedBounds.intersects(bounds) }
    }

    func links(alongPath path: [NaverCoordinate], corridorMeters: Double) async throws -> [SpeedLimitLink] {
        let projected = path.map(KoreaCoordinateConverter.project)
        guard let bounds = UTMKBounds(points: projected)?.expanded(by: corridorMeters) else { return [] }
        return links.filter { $0.projectedBounds.intersects(bounds) }
    }
}

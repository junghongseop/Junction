//
//  SpeedLimitLink.swift
//  DriveInGyeongbuk
//
//  제한속도 도메인 모델.
//
//  데이터 출처
//    번들에 포함된 `gyeongbuk_speed_limits.sqlite` (34MB).
//    국가표준노드링크(MOCT_LINK) 경상북도 전역 167,139개 링크에서
//    제한속도(`speed_kph`)·도로명·도로등급·형상만 추린 것이다.
//
//  모델을 링크(선) 단위로 잡은 이유
//    표준노드링크의 제한속도는 "이 지점의 표지판" 이 아니라 "이 도로 구간 전체"에 붙는다.
//    따라서 좌표 한 점이 아니라 폴리라인을 가진 `SpeedLimitLink` 가 원천 데이터의
//    실제 모양이다. 주행 중 안내는 현재 위치를 링크에 스냅(`SpeedLimitMatch`)해서 만든다.
//
//  이 데이터셋에 없는 것 (별도 소스가 필요하다)
//    - 단속 카메라 위치 / 구간단속 : 공공데이터포털 무인교통단속카메라 표준 데이터
//    - 어린이·노인 보호구역        : 보호구역 표준 데이터
//    - 가변 제한속도(우천 시 감속 등)
//

import Foundation

/// 표준노드링크 도로 등급(`road_rank`).
///
/// 원본은 문자열 코드(`"101"` 등)다. 제한속도의 신뢰도와 안내 문구를 등급별로
/// 다르게 가져가야 해서 열거형으로 정리했다.
nonisolated enum RoadRank: String, Hashable, CaseIterable {
    /// 고속국도 (예: 경부고속도로)
    case expressway = "101"
    /// 도시고속화도로
    case urbanExpressway = "102"
    /// 일반국도
    case nationalRoad = "103"
    /// 특별·광역시도
    case metropolitanRoad = "104"
    /// 국가지원지방도
    case nationalLocalRoad = "105"
    /// 지방도
    case localRoad = "106"
    /// 시군도
    case cityCountyRoad = "107"
    /// 위 어디에도 해당하지 않는 값.
    case unknown = "-"

    init(code: String?) {
        guard let code, let rank = RoadRank(rawValue: code) else {
            self = .unknown
            return
        }
        self = rank
    }

    var koreanTitle: String {
        switch self {
        case .expressway: return "고속국도"
        case .urbanExpressway: return "도시고속화도로"
        case .nationalRoad: return "일반국도"
        case .metropolitanRoad: return "특별·광역시도"
        case .nationalLocalRoad: return "국가지원지방도"
        case .localRoad: return "지방도"
        case .cityCountyRoad: return "시군도"
        case .unknown: return "기타 도로"
        }
    }

    var englishTitle: String {
        switch self {
        case .expressway: return "Expressway"
        case .urbanExpressway: return "Urban expressway"
        case .nationalRoad: return "National highway"
        case .metropolitanRoad: return "Metropolitan road"
        case .nationalLocalRoad: return "National-support local road"
        case .localRoad: return "Provincial road"
        case .cityCountyRoad: return "City/county road"
        case .unknown: return "Other road"
        }
    }

    /// 자동차 전용도로인지. 보행자·이면도로 안내를 걸러 낼 때 쓴다.
    var isMotorway: Bool {
        self == .expressway || self == .urbanExpressway
    }
}

/// 제한속도가 붙은 도로 링크 한 개.
nonisolated struct SpeedLimitLink: Identifiable, Hashable {

    /// 표준노드링크 링크 ID. 데이터셋 안에서 유일하다.
    var id: Int64 { linkID }
    var linkID: Int64

    /// 제한속도(km/h).
    var limitKPH: Int
    /// 도로명. 원본에 비어 있는 링크가 약 3%(5,169개) 있어 옵셔널이다.
    var roadName: String?
    var roadRank: RoadRank

    /// 시작 노드 ID.
    var fromNodeID: Int64
    /// 종료 노드 ID. `fromNode → toNode` 가 이 링크의 통행 방향이다.
    var toNodeID: Int64

    /// 링크 형상(WGS84). 지도에 그릴 때 쓴다.
    var path: [NaverCoordinate]
    /// 링크 형상(EPSG:5179 평면, 미터). 위치 매칭 계산은 전부 이쪽으로 한다.
    var projectedPath: [UTMKPoint]

    /// 링크 전체 길이(m).
    var lengthMeters: Double
    /// 링크를 감싸는 평면 사각 영역.
    var projectedBounds: UTMKBounds

    /// 사용자에게 보여 줄 도로 이름. 이름이 없으면 등급으로 대신한다.
    var displayName: String {
        if let roadName, !roadName.isEmpty { return roadName }
        return roadRank.koreanTitle
    }

    /// 제한속도를 신뢰해도 되는지.
    ///
    /// 표준노드링크는 이면도로·골목에 10~20km/h 같은 값을 넣어 두는 경우가 많다.
    /// 실제 표지판이 아니라 통행 가능 속도에 가까우므로 초과 경고를 띄우면 오탐이 된다.
    /// 주행 안내에서는 이 값이 `false` 인 링크의 경고를 억제한다.
    var isReliableLimit: Bool {
        limitKPH >= 30
    }

    /// 현재 위치에서 이 링크까지의 최단거리와 스냅 지점을 구한다.
    /// - Parameter point: EPSG:5179 평면 좌표.
    func nearestPoint(to point: UTMKPoint) -> (snapped: UTMKPoint, distance: Double, progressMeters: Double)? {
        PolylineMath.nearestPoint(on: projectedPath, to: point)
    }
}

/// 현재 위치를 특정 링크에 스냅한 결과.
nonisolated struct SpeedLimitMatch: Identifiable, Hashable {
    var id: Int64 { link.linkID }

    var link: SpeedLimitLink
    /// 링크 위로 내린 수선의 발(WGS84).
    var snappedCoordinate: NaverCoordinate
    /// 원래 위치에서 링크까지의 수직 거리(m). 작을수록 이 도로 위에 있을 확률이 높다.
    var lateralDistanceMeters: Double
    /// 링크 시작점에서 스냅 지점까지의 거리(m).
    var progressMeters: Double

    var limitKPH: Int { link.limitKPH }
    var roadName: String? { link.roadName }
    var roadRank: RoadRank { link.roadRank }
}

// MARK: - 에러

nonisolated enum SpeedLimitError: Error, LocalizedError, Equatable {
    /// 번들에서 제한속도 DB 를 찾지 못함.
    case databaseNotFound(String)
    /// SQLite 열기/질의 실패.
    case database(String)
    /// 링크 형상(GSL1) 파싱 실패.
    case malformedGeometry(linkID: Int64, reason: String)
    /// 데이터셋 커버리지(경상북도) 밖.
    case outsideCoverage
    /// 아직 `prepare(...)` 를 부르지 않음.
    case notPrepared

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let name):
            return "제한속도 데이터(\(name))를 번들에서 찾지 못했습니다."
        case .database(let reason):
            return "제한속도 데이터를 읽지 못했습니다. (\(reason))"
        case .malformedGeometry(let linkID, let reason):
            return "링크 \(linkID) 의 형상 데이터가 손상되었습니다. (\(reason))"
        case .outsideCoverage:
            return "경상북도 밖이라 제한속도 정보를 제공할 수 없습니다."
        case .notPrepared:
            return "제한속도 정보가 아직 준비되지 않았습니다. prepare(for:) 를 먼저 호출해 주세요."
        }
    }
}

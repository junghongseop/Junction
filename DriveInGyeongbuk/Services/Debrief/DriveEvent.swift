//
//  DriveEvent.swift
//  DriveInGyeongbuk
//
//  주행 중 **객관적으로 일어난 일** 하나.
//
//  이 타입이 GPS 원본과 LLM 사이의 방화벽이다.
//    · 만드는 쪽: `DriveEventDetector` — 규칙 기반, AI 없이 동작한다.
//    · 쓰는 쪽: LLM — "이 중 무엇을 설명할지" 고를 때만 본다.
//
//  그래서 이 타입은 **판단을 담지 않는다.** "제한속도 60 구간에서 74km/h 로 9초"까지가
//  이벤트고, "위반이다 / 과태료 얼마다" 는 여기에도 LLM 에도 없다. 그 설명은
//  `DebriefTopic` 의 검증된 문장에서만 나온다.
//

import Foundation

nonisolated struct DriveEvent: Identifiable, Hashable {

    /// `event_1` 형태. LLM 응답이 이 값으로 사건을 되짚어 준다.
    var id: String
    var kind: Kind
    var occurredAt: Date
    var coordinate: NaverCoordinate?
    /// 도로명은 표지판과 대조해야 해서 한국어 원문을 그대로 둔다.
    var roadName: String?

    /// 코드가 계산한 수치들. 전부 측정값이거나 공공데이터에서 온 값이다.
    var facts: [Fact]

    /// 사람이 읽는 한 줄. 프롬프트와 요약 화면이 같이 쓴다.
    var summary: String

    /// 이 사건과 이어지는 안내 주제. 앞쪽일수록 관련이 깊다.
    var relatedTopicIDs: [DebriefTopicID]

    enum Kind: String, Hashable, Codable {
        /// 경로 위에서 제한속도가 바뀌었다.
        case speedLimitChange = "speed_limit_change"
        /// 제한속도를 일정 시간 이상 넘긴 채로 달렸다.
        case sustainedSpeeding = "sustained_speeding"
        /// 한자리에 오래 서 있었다.
        case longStop = "long_stop"
        /// 톨게이트를 지났다.
        case tollGatePassed = "toll_gate_passed"
    }

    /// 프롬프트에 그대로 실릴 키-값. 순서를 지켜야 해서 딕셔너리가 아니다.
    struct Fact: Hashable, Codable {
        var key: String
        var value: String

        init(_ key: String, _ value: String) {
            self.key = key
            self.value = value
        }

        init(_ key: String, _ value: Int) {
            self.init(key, String(value))
        }

        init(_ key: String, _ value: Bool) {
            self.init(key, value ? "true" : "false")
        }
    }

    func fact(_ key: String) -> String? {
        facts.first { $0.key == key }?.value
    }
}

// MARK: -

/// 감지기 한 종류가 보는 입력.
///
/// 감지기는 서비스를 직접 부르지 않는다. 네트워크·DB 조회는 `DebriefService` 가 미리 끝내
/// 이 구조체에 담아 주고, 감지기는 순수 계산만 한다. 테스트하기 쉬우라고 이렇게 나눴다.
nonisolated struct DriveEventContext {

    var recording: DriveRecording

    /// `SpeedLimitService.prepare(for:)` 이후의 경로 구간. 못 불러왔으면 빈 배열.
    var speedLimitSegments: [RouteSpeedLimitSegment] = []

    /// 목적지 반경(서버 고정 2km) 안의 주정차 금지구역. 못 불러왔으면 빈 배열.
    ///
    /// ⚠️ **목적지 주변만 있다.** 경로 중간에서 선 곳이 금지구역인지는 알 수 없다.
    /// 그래서 `StopDetector` 는 이 반경 밖의 정차를 두고 아무 말도 하지 않는다.
    var enforcementZones: [EnforcementZone] = []
    /// 위 목록이 유효한 중심(= 목적지)과 반경.
    var enforcementCenter: NaverCoordinate?
    var enforcementRadiusMeters: Double = 0

    /// 경로 위 진행 위치를 빠르게 찾기 위한 색인. 경로가 없으면 nil.
    var progress: RouteProgressIndex?

    init(recording: DriveRecording,
         speedLimitSegments: [RouteSpeedLimitSegment] = [],
         enforcementZones: [EnforcementZone] = [],
         enforcementCenter: NaverCoordinate? = nil,
         enforcementRadiusMeters: Double = 0) {
        self.recording = recording
        self.speedLimitSegments = speedLimitSegments
        self.enforcementZones = enforcementZones
        self.enforcementCenter = enforcementCenter
        self.enforcementRadiusMeters = enforcementRadiusMeters
        self.progress = recording.route.map { RouteProgressIndex(path: $0.path) }
    }

    /// 주어진 좌표가 단속 데이터가 닿는 범위 안인지.
    func hasEnforcementCoverage(at coordinate: NaverCoordinate) -> Bool {
        guard let enforcementCenter else { return false }
        return enforcementCenter.distance(to: coordinate) <= enforcementRadiusMeters
    }
}

// MARK: -

/// 규칙 하나를 담당하는 감지기.
protocol DriveEventDetecting {
    /// 사건을 찾아 시간순으로 돌려준다. 찾을 게 없으면 빈 배열.
    /// - Note: 절대 실패하지 않는다. 데이터가 없으면 조용히 빈 배열이다.
    func detect(in context: DriveEventContext) -> [DriveEvent]
}

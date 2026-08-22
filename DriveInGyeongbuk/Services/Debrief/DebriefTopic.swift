//
//  DebriefTopic.swift
//  DriveInGyeongbuk
//
//  Debrief 가 설명할 수 있는 "안내 주제"와, 각 주제의 **검증된 설명 콘텐츠**.
//
//  이 파일이 이 기능의 사실 경계다.
//    · LLM 은 여기 있는 문장을 고르고 **다시 서술만** 한다.
//    · 여기 없는 법규·과태료·절차를 LLM 이 만들어 내면 안 된다.
//    · 그래서 각 주제는 근거(`source`)를 반드시 들고 다닌다.
//
//  ⚠️ 서비스 계층이므로 SwiftUI 를 모른다. 표지판 색 같은 표현은 `style` 값으로만 두고
//     실제 색은 화면(`Features/Debrief`)에서 정한다.
//

import Foundation

/// 안내 주제 식별자.
///
/// rawValue 는 LLM 응답에 그대로 실려 오므로 **바꾸면 프롬프트도 같이 고쳐야 한다.**
nonisolated enum DebriefTopicID: String, Codable, Hashable, CaseIterable {
    case speedLimitChange = "speed_limit_change"
    case speedingRule = "speeding_rule"
    case trafficCamera = "traffic_camera"
    case tollGate = "toll_gate"
    case unpaidToll = "unpaid_toll"
    case noParkingZone = "no_parking_zone"
    case noStoppingZone = "no_stopping_zone"
    case yellowLine = "yellow_line"
    /// ⚠️ 콘텐츠는 있지만 **감지 수단이 없다.**
    /// 표준노드링크·Junction 서버 어디에도 보호구역 데이터가 없어서 이벤트가 만들어지지 않는다.
    /// 데이터 소스가 생기면 감지기만 추가하면 된다.
    case schoolZone = "school_zone"
}

// MARK: - 콘텐츠

/// 한 주제의 준비된 설명.
nonisolated struct DebriefTopic: Identifiable, Hashable {

    var id: DebriefTopicID
    /// 화면 제목의 기본값. LLM 이 사건에 맞춰 다시 쓸 수 있다.
    var title: String
    /// 검증된 사실. **LLM 은 이 목록 안에서만 말할 수 있다.**
    var facts: [String]
    /// 근거. 화면 하단과 프롬프트 양쪽에 쓴다.
    var source: String
    /// 다음에 할 행동. 없으면 nil.
    var actionNote: String?
    /// 화면에 곁들일 도해.
    var visual: DebriefVisual

    init(id: DebriefTopicID,
         title: String,
         facts: [String],
         source: String,
         actionNote: String? = nil,
         visual: DebriefVisual = .none) {
        self.id = id
        self.title = title
        self.facts = facts
        self.source = source
        self.actionNote = actionNote
        self.visual = visual
    }
}

// MARK: - 도해

/// 주제에 곁들이는 그림. Figma 2·3·4 화면의 가운데 블록이 이것 하나로 통일된다.
nonisolated struct DebriefVisual: Hashable {

    /// 원형 속도 표지판 (Figma 2).
    var speedSigns: [SpeedSignSpec] = []
    /// 배지 + 설명 줄 (Figma 3 — 하이패스/일반/렌터카).
    var badgeRows: [BadgeRowSpec] = []
    /// 노면 선 견본 + 설명 줄 (Figma 4 — 흰선/황색점선/…).
    var lineRows: [LineRowSpec] = []

    static let none = DebriefVisual()

    var isEmpty: Bool { speedSigns.isEmpty && badgeRows.isEmpty && lineRows.isEmpty }
}

/// 원형 속도 표지판 하나.
nonisolated struct SpeedSignSpec: Identifiable, Hashable {
    var id = UUID()
    var speedKPH: Int
    var caption: String
    var style: Style

    /// 한국 표지판 실제 배색을 따른다. 색값은 화면이 정한다.
    enum Style: Hashable {
        /// 흰 바탕 + 빨간 테두리 — 최고속도.
        case maximum
        /// 파란 바탕 — 최저속도.
        case minimum
        /// 노란 테두리 — 어린이 보호구역.
        case schoolZone
    }
}

/// 배지 + 설명 한 줄.
nonisolated struct BadgeRowSpec: Identifiable, Hashable {
    var id = UUID()
    /// 배지에 적히는 글자. 한국 도로에서 실제로 보이는 표기는 한글 그대로 둔다.
    var badge: String
    var text: String
    var style: Style

    enum Style: Hashable {
        /// 하이패스 — 파란 차로.
        case highlighted
        /// 일반 차로 — 흰/회색.
        case neutral
        /// 참고 정보.
        case informational
    }
}

/// 노면 선 견본 + 설명 한 줄.
nonisolated struct LineRowSpec: Identifiable, Hashable {
    var id = UUID()
    var pattern: Pattern
    var text: String

    /// 연석 노면표시 규칙. 한국은 **선의 색과 개수로** 주정차 규칙을 나타낸다.
    enum Pattern: Hashable {
        /// 흰 실선 — 주차 가능.
        case white
        /// 황색 점선 — 짧은 정차만.
        case dashedYellow
        /// 황색 실선 — 주차 금지.
        case solidYellow
        /// 황색 복선 — 주정차 금지.
        case doubleYellow
        /// 적색 — 절대 금지 (소방시설 주변 등).
        case red
    }
}

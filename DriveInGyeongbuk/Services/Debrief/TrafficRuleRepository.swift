//
//  TrafficRuleRepository.swift
//  DriveInGyeongbuk
//
//  검증된 설명 콘텐츠 저장소.
//
//  왜 번들 JSON 이 아니라 Swift 리터럴인가
//    JSON 은 Xcode 동기화 그룹이 리소스로 안 넣어 주면 런타임에 조용히 사라진다.
//    콘텐츠가 통째로 비면 Debrief 가 아무 말도 못 하는 기능이 되므로, 지금은
//    컴파일 타임에 존재가 보장되는 쪽을 골랐다. 프로토콜로 감싸 두었으니
//    나중에 원격/JSON 소스로 갈아 끼우는 건 이 파일만 바꾸면 된다.
//
//  ⚠️ 문구를 고칠 때 지켜야 할 것
//    · 확인되지 않은 금액·기간·수치를 쓰지 않는다. 근거를 댈 수 없으면 빼는 게 낫다.
//    · 각 항목에 `source` 를 반드시 남긴다. 화면에도 노출된다.
//    · 겁을 주지 않는다. 목적은 "다음에 뭘 하면 되는지"를 알려 주는 것이다.
//

import Foundation

protocol TrafficRuleRepositoryProtocol {
    var allTopics: [DebriefTopic] { get }
    func topic(_ id: DebriefTopicID) -> DebriefTopic?
    func topics(for ids: [DebriefTopicID]) -> [DebriefTopic]
}

extension TrafficRuleRepositoryProtocol {
    func topics(for ids: [DebriefTopicID]) -> [DebriefTopic] {
        // 중복 제거하되 들어온 순서(= 사건에서의 중요도 순)를 지킨다.
        var seen: Set<DebriefTopicID> = []
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return topic(id)
        }
    }
}

// MARK: -

struct TrafficRuleRepository: TrafficRuleRepositoryProtocol {

    let allTopics: [DebriefTopic]

    init(topics: [DebriefTopic] = TrafficRuleRepository.builtInTopics) {
        self.allTopics = topics
    }

    func topic(_ id: DebriefTopicID) -> DebriefTopic? {
        allTopics.first { $0.id == id }
    }
}

// MARK: - 내장 콘텐츠

extension TrafficRuleRepository {

    static let builtInTopics: [DebriefTopic] = [
        speedLimitChange,
        speedingRule,
        trafficCamera,
        tollGate,
        unpaidToll,
        noParkingZone,
        noStoppingZone,
        yellowLine,
        schoolZone
    ]

    // MARK: 속도

    static let speedLimitChange = DebriefTopic(
        id: .speedLimitChange,
        title: "Speed limits change often here",
        facts: [
            "A posted limit takes effect from the sign onward. There is no gradual transition zone before it.",
            "Limits drop in steps when an expressway feeds into a national road and then into a town, often 80 to 60 to 50 km/h within a few kilometres.",
            "Most city roads are 50 km/h and residential side streets are 30 km/h under the nationwide Safety Speed 5030 rule.",
            "A white circle with a red border is the maximum speed. A blue circle is a minimum speed, used mainly in expressway tunnels."
        ],
        source: "도로교통법 시행규칙 별표6 (안전표지) · 안전속도 5030",
        actionNote: "When a new circular sign comes into view, slow down before you reach it rather than after.",
        visual: DebriefVisual(speedSigns: [
            SpeedSignSpec(speedKPH: 60, caption: "Maximum", style: .maximum),
            SpeedSignSpec(speedKPH: 30, caption: "Minimum", style: .minimum)
        ])
    )

    static let speedingRule = DebriefTopic(
        id: .speedingRule,
        title: "How speeding is handled",
        facts: [
            "Enforcement is mostly automated. Very little of it is a police car pulling you over.",
            "The camera photographs the vehicle, not the driver, so the notice goes to the registered owner.",
            "In a rental car the rental company receives the notice and passes the charge on to you, usually with a handling fee.",
            "Penalties rise with how far over the limit you were, and they are considerably steeper inside a school zone."
        ],
        // TODO: 구간별 과태료 금액표는 경찰청 고시를 확인한 뒤에만 넣는다. 지금은 의도적으로 비워 둔다.
        source: "도로교통법 제17조 · 제160조",
        actionNote: "If a notice reaches you through a rental company, they can give you the ticket number so you can check it yourself."
    )

    static let trafficCamera = DebriefTopic(
        id: .trafficCamera,
        title: "Where the cameras are",
        facts: [
            "Fixed speed cameras are signposted in advance, and navigation apps announce them.",
            "Section enforcement is different: two gantries measure your average speed between them, so braking only at the camera does not help.",
            "The same intersection cameras also record running a red light.",
            "School-zone cameras operate around the clock."
        ],
        source: "경찰청 무인교통단속장비 공공데이터",
        actionNote: "On an unfamiliar road, keeping to the posted limit is simpler than guessing where the cameras are."
    )

    // MARK: 톨게이트

    static let tollGate = DebriefTopic(
        id: .tollGate,
        title: "How Korean toll gates work",
        facts: [
            "Expressways charge by distance. You enter at one gate and pay at the gate where you exit.",
            "Blue Hi-Pass lanes are electronic only and need a working in-car terminal. Do not enter one without it.",
            "Grey lanes marked 일반 are staffed. Stop there and pay by cash or card.",
            "Most rental cars come with a Hi-Pass terminal, and the tolls are settled through the rental agreement."
        ],
        source: "한국도로공사 (ex.co.kr)",
        actionNote: "If you enter a Hi-Pass lane without a terminal, keep driving. Never reverse in a toll plaza — you can settle the toll afterwards.",
        visual: DebriefVisual(badgeRows: [
            BadgeRowSpec(badge: "Hi-Pass", text: "Needs an in-car terminal", style: .highlighted),
            BadgeRowSpec(badge: "일반", text: "Stop and pay by cash or card", style: .neutral),
            BadgeRowSpec(badge: "Rental", text: "Usually billed to your rental", style: .informational)
        ])
    )

    static let unpaidToll = DebriefTopic(
        id: .unpaidToll,
        title: "If a toll went unpaid",
        facts: [
            "Passing a Hi-Pass lane without a valid terminal records an unpaid toll. It is not treated as an instant fine.",
            "Unpaid tolls can be looked up and settled on the Korea Expressway Corporation site, ex.co.kr.",
            "The customer line 1588-2504 handles unpaid tolls and has English support.",
            "For a rental car the company is billed first and charges you afterwards, so it can surface days later."
        ],
        source: "한국도로공사 (ex.co.kr) · 고객센터 1588-2504",
        actionNote: "Not sure whether today's toll went through? Check ex.co.kr or call 1588-2504."
    )

    // MARK: 주정차

    static let noParkingZone = DebriefTopic(
        id: .noParkingZone,
        title: "What the kerb lines mean",
        facts: [
            "The colour and count of the line at the kerb carry the parking rule. There is often no separate sign.",
            "A single yellow line means brief stops only. A double yellow line means no stopping at all, not even for a moment.",
            "Red lines mark places where stopping is never allowed, such as beside fire equipment.",
            "Enforcement is frequently by camera, or by a patrol that photographs the car twice a few minutes apart."
        ],
        source: "도로교통법 제32·33조 · 노면표시 설치·관리 매뉴얼",
        actionNote: "If you have to stop briefly, stay with the car. A driver in the seat is what separates a stop from parking.",
        visual: DebriefVisual(lineRows: [
            LineRowSpec(pattern: .white, text: "Parking allowed"),
            LineRowSpec(pattern: .dashedYellow, text: "Brief stops only"),
            LineRowSpec(pattern: .solidYellow, text: "No parking"),
            LineRowSpec(pattern: .doubleYellow, text: "No stopping at all"),
            LineRowSpec(pattern: .red, text: "Never, under any condition")
        ])
    )

    static let noStoppingZone = DebriefTopic(
        id: .noStoppingZone,
        title: "Sections where stopping is restricted",
        facts: [
            "Some rules apply whether or not a line is painted: no stopping within 5 m of an intersection, a crosswalk or a fire hydrant, and within 10 m of a bus stop.",
            "Local governments designate their own restricted sections on top of that, and those can be time-limited — for example 08:00 to 20:00 on weekdays only.",
            "Sections marked as absolute are enforced at every hour, including weekends and public holidays.",
            "Members of the public can report a parked car through a mobile app, so an empty-looking street is not a safe sign."
        ],
        source: "도로교통법 제32·33조 · 지자체 주정차금지구역 공공데이터",
        actionNote: "This app can show the restricted sections around your destination before you arrive."
    )

    static let yellowLine = DebriefTopic(
        id: .yellowLine,
        title: "Yellow lines down the middle",
        facts: [
            "A yellow line along the centre of the road separates opposing traffic. A solid one must not be crossed.",
            "Crossing a solid centre line to overtake or to turn around is treated as one of the twelve serious violations.",
            "That matters because those violations fall outside the usual insurance settlement if a collision follows.",
            "A yellow line at the kerb is a different rule entirely — that one is about parking, not about crossing."
        ],
        source: "도로교통법 제13조 · 교통사고처리특례법 (12대 중과실)",
        actionNote: "If you miss a turn, carry on to the next legal U-turn point rather than crossing the centre line."
    )

    // MARK: 보호구역 (감지 수단 없음)

    /// ⚠️ 콘텐츠만 있고 이 주제를 켜 줄 **이벤트가 만들어지지 않는다.**
    /// 보호구역 좌표 데이터가 앱에 없기 때문이다 (`DebriefTopicID.schoolZone` 주석 참고).
    static let schoolZone = DebriefTopic(
        id: .schoolZone,
        title: "School zones",
        facts: [
            "A school zone is limited to 30 km/h, and that limit applies around the clock, not only during school hours.",
            "They are marked with red road surface, yellow signs and 어린이보호구역 painted on the road.",
            "Penalties for speeding and for illegal parking are roughly doubled inside a school zone.",
            "Between 08:00 and 20:00 the penalties are increased further."
        ],
        source: "도로교통법 제12조 (어린이 보호구역)",
        actionNote: "Red asphalt is the clearest cue. When the surface turns red, drop to 30 km/h.",
        visual: DebriefVisual(speedSigns: [
            SpeedSignSpec(speedKPH: 30, caption: "School zone", style: .schoolZone)
        ])
    )
}

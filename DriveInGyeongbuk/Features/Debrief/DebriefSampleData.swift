//
//  DebriefSampleData.swift
//  DriveInGyeongbuk
//
//  [개발/미리보기 전용] 손으로 만든 Debrief 결과.
//
//  왜 필요한가
//    화면만 손볼 때까지 네트워크·SQLite·LLM 을 다 태울 이유가 없다. 여기 있는 값은
//    실제 파이프라인이 내놓는 것과 같은 모양이라, 화면 쪽 작업은 이것만으로 끝난다.
//
//  ⚠️ 이건 화면 확인용이다. **감지 규칙이 맞는지는 이걸로 확인할 수 없다.**
//     그건 실제 경로로 돌리는 `DebriefSimulationView` 의 몫이다.
//     제품 코드가 아니므로 출시 전에 `Test/` 와 함께 걷어낸다.
//

import Foundation

enum DebriefSampleData {

    /// 거리·시간만 든 최소 경로. 감지에는 쓰이지 않고 헤드라인 표기용이다.
    private static func sampleRoute(distanceMeters: Int, durationSeconds: Int) -> DrivingRoute {
        DrivingRoute(
            option: .fastest,
            start: NaverCoordinate(latitude: 36.0190, longitude: 129.3435),
            goal: NaverCoordinate(latitude: 35.8347, longitude: 129.2194),
            path: [],
            sections: [],
            steps: [],
            bounds: nil,
            distance: distanceMeters,
            duration: durationSeconds,
            tollFare: 0,
            taxiFare: 0,
            fuelPrice: 0
        )
    }

    /// 포항 → 경주. 제한속도 변화 직후 과속 + 톨게이트 통과.
    static let firstDriveToGyeongju: Debrief = {
        let started = Date(timeIntervalSince1970: 1_770_000_000)

        let speedingEvent = DriveEvent(
            id: "event_2",
            kind: .sustainedSpeeding,
            occurredAt: started.addingTimeInterval(720),
            coordinate: NaverCoordinate(latitude: 35.9612, longitude: 129.3210),
            roadName: "산업로",
            facts: [
                .init("speedLimitKPH", 60),
                .init("peakSpeedKPH", 78),
                .init("averageSpeedKPH", 74),
                .init("durationSeconds", 9),
                .init("startedRightAfterLimitDrop", true),
                .init("previousSpeedLimitKPH", 80),
                .init("metersAfterNewSignPost", 180),
                .init("roadName", "산업로")
            ],
            summary: "Held about 74 km/h for 9 s just after the limit dropped to 60 km/h.",
            relatedTopicIDs: [.speedLimitChange, .speedingRule, .trafficCamera]
        )

        let tollEvent = DriveEvent(
            id: "event_3",
            kind: .tollGatePassed,
            occurredAt: started.addingTimeInterval(1_140),
            coordinate: NaverCoordinate(latitude: 35.8562, longitude: 129.2820),
            roadName: "경주요금소",
            facts: [
                .init("tollGateName", "경주요금소"),
                .init("routeTotalTollFareKRW", 2_400),
                .init("tollGateCountOnRoute", 1)
            ],
            summary: "Passed 경주요금소 toll gate on the route.",
            relatedTopicIDs: [.tollGate, .unpaidToll]
        )

        let limitChangeEvent = DriveEvent(
            id: "event_1",
            kind: .speedLimitChange,
            occurredAt: started,
            coordinate: nil,
            roadName: nil,
            facts: [
                .init("changeCount", 4),
                .init("sequenceKPH", "80 → 60 → 80 → 50"),
                .init("highestLimitKPH", 80),
                .init("lowestLimitKPH", 50)
            ],
            summary: "The speed limit changed 4 times along the route (80 → 60 → 80 → 50 km/h).",
            relatedTopicIDs: [.speedLimitChange, .trafficCamera]
        )

        let lessons = [
            DebriefLesson(
                lesson: .init(eventID: speedingEvent.id,
                              topicID: .speedLimitChange,
                              title: "Watch for speed limit changes",
                              explanation: "The limit dropped from 80 to 60 km/h and you kept close to 74 km/h for about nine seconds afterwards. In Korea a posted limit takes effect from the sign onward — there is no run-off before it. When a new circular sign comes into view, slow down before you reach it rather than after.",
                              reason: "Speed dropped sharply and the driver held the previous speed."),
                event: speedingEvent,
                topic: TrafficRuleRepository.speedLimitChange
            ),
            DebriefLesson(
                lesson: .init(eventID: tollEvent.id,
                              topicID: .tollGate,
                              title: "You passed a toll gate",
                              explanation: "You went through 경주요금소 today. Expressways here charge by distance, so you enter at one gate and settle at the one where you leave. Blue Hi-Pass lanes are electronic and need a terminal in the car; the grey 일반 lanes are staffed and take cash or card. Most rentals come with a terminal and bill it to your agreement.",
                              reason: "First drive in Korea and a toll gate was passed."),
                event: tollEvent,
                topic: TrafficRuleRepository.tollGate
            )
        ]

        let recording = DriveRecording(
            // 위치 기록이 없으면 `distanceMeters` 가 경로 거리로 물러선다.
            // 헤드라인의 "· 32 km" 를 살리려고 거리만 든 최소 경로를 붙여 둔다.
            route: sampleRoute(distanceMeters: 32_000, durationSeconds: 2_040),
            originName: "Pohang",
            destinationName: "Gyeongju",
            startedAt: started,
            endedAt: started.addingTimeInterval(2_040),
            samples: [],
            isFirstDriveInKorea: true
        )

        return Debrief(
            id: recording.id,
            recording: recording,
            events: [limitChangeEvent, speedingEvent, tollEvent],
            report: DebriefReport(
                summary: "Your first drive in Gyeongbuk is complete.",
                lessons: lessons.map(\.lesson)
            ),
            lessons: lessons
        )
    }()

    /// 주정차 금지구간에 세운 경우. (피그마 4번 화면)
    static let restrictedStop: DebriefLesson = {
        let event = DriveEvent(
            id: "event_4",
            kind: .longStop,
            occurredAt: Date(timeIntervalSince1970: 1_770_002_100),
            coordinate: NaverCoordinate(latitude: 35.8347, longitude: 129.2194),
            roadName: "첨성로",
            facts: [
                .init("durationMinutes", 6),
                .init("insideRestrictedZone", true),
                .init("checkedAgainstOfficialZoneData", true),
                .init("roadName", "첨성로"),
                .init("restrictionType", "absolute"),
                .init("restrictionTypeKorean", "절대금지"),
                .init("prohibitedAtThatTime", true),
                .init("prohibitedHours", "매일 00:00~24:00"),
                .init("metersFromZone", 8)
            ],
            summary: "Stopped for about 6 min on 첨성로, inside a section where parking was restricted at that hour.",
            relatedTopicIDs: [.noStoppingZone, .noParkingZone]
        )

        return DebriefLesson(
            lesson: .init(eventID: event.id,
                          topicID: .noParkingZone,
                          title: "You stopped where stopping is limited",
                          explanation: "You were parked on 첨성로 for about six minutes, inside a section the city has marked as no-parking at all hours. The kerb line carries the rule here rather than a sign: a single yellow line allows a brief stop, a double yellow line allows none at all. If you need to pause, staying in the driver's seat is what separates a stop from parking.",
                          reason: "The stop overlapped an absolute restriction and lasted several minutes."),
            event: event,
            topic: TrafficRuleRepository.noParkingZone
        )
    }()

    /// 아무 사건도 없었던 주행. 빈 상태 화면 확인용.
    static let uneventfulDrive: Debrief = {
        let started = Date(timeIntervalSince1970: 1_770_100_000)
        let recording = DriveRecording(
            route: sampleRoute(distanceMeters: 24_000, durationSeconds: 1_500),
            originName: "Andong",
            destinationName: "Yecheon",
            startedAt: started,
            endedAt: started.addingTimeInterval(1_500),
            samples: [],
            isFirstDriveInKorea: false
        )
        return Debrief(
            id: recording.id,
            recording: recording,
            events: [],
            report: DebriefReport(summary: "Drive complete.", lessons: []),
            lessons: []
        )
    }()
}

//
//  DriveEventDetector.swift
//  DriveInGyeongbuk
//
//  감지기들을 한 줄로 세워 놓고 주행 기록 하나를 통과시킨다.
//
//  이 계층에 AI 는 없다. 같은 기록을 두 번 넣으면 같은 사건이 나온다 — Debrief 가
//  "무엇이 있었는가"를 두고는 흔들리지 않게 하려는 것이 목적이다. 흔들려도 되는 건
//  그 다음 단계, 무엇을 먼저 설명할지 고르는 쪽이다.
//
//  감지기를 늘리려면 `DriveEventDetecting` 하나 더 만들어 `detectors` 에 넣으면 된다.
//

import Foundation

protocol DriveEventDetectorProtocol {
    func events(in context: DriveEventContext) -> [DriveEvent]
}

nonisolated struct DriveEventDetector: DriveEventDetectorProtocol {

    /// 한 번의 Debrief 에 담을 사건 수 상한. 너무 많으면 프롬프트만 길어지고
    /// 고르는 쪽도 흐려진다.
    var maximumEventCount = 8

    private let detectors: [DriveEventDetecting]

    init(detectors: [DriveEventDetecting] = DriveEventDetector.defaultDetectors) {
        self.detectors = detectors
    }

    static var defaultDetectors: [DriveEventDetecting] {
        [
            SpeedLimitChangeDetector(),
            SustainedSpeedingDetector(),
            StopDetector(),
            TollGatePassDetector()
        ]
    }

    func events(in context: DriveEventContext) -> [DriveEvent] {

        let detected = detectors
            .flatMap { $0.detect(in: context) }
            .sorted { $0.occurredAt < $1.occurredAt }
            .prefix(maximumEventCount)

        // ID 는 여기서 한 번에 매긴다. 감지기별로 매기면 서로 겹친다.
        return detected.enumerated().map { offset, event in
            var event = event
            event.id = "event_\(offset + 1)"
            return event
        }
    }
}

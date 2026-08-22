//
//  TollGatePassDetector.swift
//  DriveInGyeongbuk
//
//  "톨게이트를 지났는가."
//
//  `TollGateService` 는 아직 껍데기지만 이 감지기는 그것을 기다리지 않는다.
//  경로 안내 문구에서 톨게이트 스텝을 이미 골라 둔 `DrivingRoute.tollGateSteps` 와,
//  실제로 그 좌표 근처를 지났는지를 보는 주행 기록만 있으면 되기 때문이다.
//
//  차로 안내(어느 차로로 붙어야 하는지)는 여전히 못 한다 — 영업소별 차로 구성 데이터가
//  없다. 하지만 Debrief 가 하려는 건 "지나간 뒤의 설명"이라 그것 없이도 성립한다.
//

import Foundation

nonisolated struct TollGatePassDetector: DriveEventDetecting {

    /// 톨게이트 좌표에 이만큼 가까이 갔으면 통과한 것으로 본다(m).
    /// 영업소는 폭이 넓고 안내 스텝 좌표가 정확히 게이트 위가 아닐 수 있어 넉넉히 잡는다.
    var passToleranceMeters: Double = 250

    func detect(in context: DriveEventContext) -> [DriveEvent] {

        guard let route = context.recording.route else { return [] }
        let steps = route.tollGateSteps
        guard !steps.isEmpty else { return [] }

        var events: [DriveEvent] = []

        for step in steps {
            // 실제로 그 근처를 지났는지 확인한다. 경로에 있었어도 중간에 그만뒀을 수 있다.
            guard let sample = context.recording.firstSample(near: step.coordinate,
                                                             radiusMeters: passToleranceMeters) else { continue }

            var facts: [DriveEvent.Fact] = []
            if let name = step.quotedPlaceName {
                facts.append(.init("tollGateName", name))
            }
            // 통행료는 경로 전체 합계다. 게이트별 금액이 아니다 — 문구가 헷갈리지 않게 키에 담았다.
            if route.tollFare > 0 {
                facts.append(.init("routeTotalTollFareKRW", route.tollFare))
            }
            facts.append(.init("tollGateCountOnRoute", steps.count))

            let name = step.quotedPlaceName
            let summary = name.map { "Passed \($0) toll gate on the route." }
                ?? "Passed a toll gate on the route."

            events.append(DriveEvent(
                id: "",   // 최종 ID 는 `DriveEventDetector` 가 시간순으로 매긴다.
                kind: .tollGatePassed,
                occurredAt: sample.timestamp,
                coordinate: step.coordinate,
                roadName: name,
                facts: facts,
                summary: summary,
                relatedTopicIDs: [.tollGate, .unpaidToll]
            ))
        }

        return events.sorted { $0.occurredAt < $1.occurredAt }
    }
}

// MARK: -

extension RouteStep {

    /// 안내 문구에 따옴표로 묶여 있는 지명. `'경주요금소' 방면` 에서 `경주요금소` 를 꺼낸다.
    ///
    /// 네이버 안내 문구는 지명을 작은따옴표나 큰따옴표로 감싸 준다. 문구 형식이 바뀌면
    /// 그냥 `nil` 이 되고, 이걸 쓰는 쪽은 지명 없는 문장으로 물러선다.
    var quotedPlaceName: String? {
        for quote in ["'", "\""] {
            let parts = instructions.split(separator: Character(quote), omittingEmptySubsequences: false)
            if parts.count >= 3 {
                let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return name }
            }
        }
        return nil
    }
}

//
//  SpeedLimitChangeDetector.swift
//  DriveInGyeongbuk
//
//  "오늘 제한속도가 몇 번 바뀌었는가."
//
//  경상북도를 가로지르면 고속도로 → 국도 → 시내로 내려오면서 80 → 60 → 50 식으로
//  단계가 계속 떨어진다. 한국 도로를 처음 달리는 사람에게는 이 잦은 변화 자체가
//  낯선 정보라서, 개별 구간이 아니라 **주행 전체를 한 문장으로** 요약해 준다.
//
//  입력은 `SpeedLimitService.prepare(for:)` 가 만들어 둔 경로 구간이다.
//  실제로 지나간 구간만 센다 — 목적지 전에 주행을 끝냈으면 그 뒤 구간은 없던 일이다.
//

import Foundation

nonisolated struct SpeedLimitChangeDetector: DriveEventDetecting {

    /// 이보다 적게 바뀌었으면 이야깃거리가 아니다.
    var minimumChangeCount = 2

    func detect(in context: DriveEventContext) -> [DriveEvent] {

        let traversed = traversedSegments(in: context)
        // 표준노드링크가 이면도로에 넣어 둔 10~20km/h 는 표지판 값이 아니다.
        let limits = traversed.filter(\.isReliableLimit).compactMap(\.limitKPH)
        guard limits.count >= 2 else { return [] }

        // 연속으로 같은 값이 이어지는 건 한 번으로 친다.
        var sequence: [Int] = []
        for limit in limits where limit != sequence.last {
            sequence.append(limit)
        }

        let changeCount = max(0, sequence.count - 1)
        guard changeCount >= minimumChangeCount else { return [] }

        let occurredAt = context.recording.startedAt
        let sequenceText = sequence.map(String.init).joined(separator: " → ")

        return [DriveEvent(
            id: "",   // 최종 ID 는 `DriveEventDetector` 가 시간순으로 매긴다.
            kind: .speedLimitChange,
            occurredAt: occurredAt,
            coordinate: nil,
            roadName: nil,
            facts: [
                .init("changeCount", changeCount),
                .init("sequenceKPH", sequenceText),
                .init("highestLimitKPH", sequence.max() ?? 0),
                .init("lowestLimitKPH", sequence.min() ?? 0)
            ],
            summary: "The speed limit changed \(changeCount) times along the route (\(sequenceText) km/h).",
            relatedTopicIDs: [.speedLimitChange, .trafficCamera]
        )]
    }

    /// 실제로 지나간 구간만 남긴다.
    private func traversedSegments(in context: DriveEventContext) -> [RouteSpeedLimitSegment] {
        let segments = context.speedLimitSegments
        guard !segments.isEmpty else { return [] }

        // 경로 색인이나 샘플이 없으면 어디까지 갔는지 알 수 없다. 전체를 지나갔다고 본다.
        guard let progress = context.progress,
              let lastSample = context.recording.samples.last else { return segments }

        progress.rewind()
        guard let lastIndex = progress.index(for: lastSample.coordinate) else { return segments }
        progress.rewind()

        return segments.filter { $0.startPathIndex <= lastIndex }
    }
}

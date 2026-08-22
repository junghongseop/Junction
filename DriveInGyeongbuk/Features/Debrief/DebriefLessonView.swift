//
//  DebriefLessonView.swift
//  DriveInGyeongbuk
//
//  안내 카드 하나를 펼친 화면. (피그마 "Debrief 2·3·4")
//
//  시안의 세 화면은 가운데 도해만 다르고 나머지 구조가 같다. 그래서 화면을 셋으로
//  나누지 않고 하나로 두고, 도해는 `DebriefVisualView` 가 주제에 맞춰 고른다.
//  주제가 늘어도 이 파일은 그대로다.
//
//  화면에 나오는 문장의 출처
//    · 헤드라인·설명 → LLM 이 이 주행에 맞춰 다시 쓴 것
//    · 도해·Tip·출처 → `DebriefTopic` 의 검증된 콘텐츠 (LLM 이 만지지 않는다)
//  섞이지 않게 하는 게 이 화면의 요지라서, 아래 `source` 줄을 항상 노출한다.
//

import SwiftUI

struct DebriefLessonView: View {

    let lesson: DebriefLesson

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                DebriefVisualView(visual: lesson.topic.visual)
                explanation
                source
            }
            .padding(.horizontal, DebriefStyle.horizontalMargin)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .safeAreaInset(edge: .bottom) {
            if let actionNote = lesson.topic.actionNote {
                DebriefTipCard(label: tipLabel, message: actionNote)
                    .padding(.horizontal, DebriefStyle.horizontalMargin)
                    .padding(.bottom, 12)
            }
        }
        .debriefBackground()
        .navigationTitle("Debrief")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: -

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebriefStyle.eyebrow("On today's drive")

            Text(lesson.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DebriefStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(DebriefStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explanation: some View {
        Text(lesson.explanation)
            .font(.system(size: 16))
            .lineSpacing(4)
            .foregroundStyle(DebriefStyle.primaryText.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 이 설명의 사실 근거가 어디서 왔는지. LLM 이 지어낸 게 아니라는 표시이기도 하다.
    private var source: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 12))
            Text(lesson.topic.source)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DebriefStyle.secondaryText.opacity(0.8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 문구

    /// 헤드라인 아래 한 줄. **감지된 사실만** 쓴다 — 여기는 LLM 이 만지는 자리가 아니다.
    private var subtitle: String? {
        guard let event = lesson.event else { return nil }

        switch event.kind {
        case .speedLimitChange:
            return event.fact("sequenceKPH").map { "\($0) km/h on your route." }

        case .sustainedSpeeding:
            guard let limit = event.fact("speedLimitKPH"),
                  let speed = event.fact("averageSpeedKPH"),
                  let seconds = event.fact("durationSeconds") else { return nil }
            let road = event.roadName.map { "\($0) · " } ?? ""
            return "\(road)about \(speed) km/h for \(seconds) s where the limit was \(limit) km/h."

        case .tollGatePassed:
            guard let name = event.fact("tollGateName") else { return "Expressways charge by distance." }
            return "\(name). Expressways charge by distance."

        case .longStop:
            guard let minutes = event.fact("durationMinutes") else { return nil }
            guard event.fact("insideRestrictedZone") == "true" else {
                return "Stopped for \(minutes) min, clear of any restricted section."
            }
            let road = event.roadName ?? "the road"
            return "\(road) · stopped for about \(minutes) min."
        }
    }

    /// Tip 카드 라벨. 시안이 화면마다 다른 말을 쓰길래 사건 종류로 갈랐다.
    private var tipLabel: String {
        switch lesson.event?.kind {
        case .tollGatePassed: return "If you're unsure"
        case .longStop: return "Where you were"
        default: return "Remember"
        }
    }
}

#Preview("제한속도") {
    NavigationStack {
        DebriefLessonView(lesson: DebriefSampleData.firstDriveToGyeongju.lessons[0])
    }
    .preferredColorScheme(.dark)
}

#Preview("톨게이트") {
    NavigationStack {
        DebriefLessonView(lesson: DebriefSampleData.firstDriveToGyeongju.lessons[1])
    }
    .preferredColorScheme(.dark)
}

#Preview("주정차") {
    NavigationStack {
        DebriefLessonView(lesson: DebriefSampleData.restrictedStop)
    }
    .preferredColorScheme(.dark)
}

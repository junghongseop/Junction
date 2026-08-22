//
//  DebriefVisualView.swift
//  DriveInGyeongbuk
//
//  `DebriefVisual` 을 그리는 곳.
//
//  시안은 2·3·4번 화면이 서로 다른 레이아웃처럼 보이지만, 실은 "헤드라인 아래 도해 한 덩어리"
//  라는 같은 구조다. 그래서 화면을 세 개 만들지 않고 도해만 세 종류로 두었다.
//  주제가 늘어도 화면은 그대로고 여기 `case` 하나가 는다.
//
//  ⚠️ 색은 여기서만 정한다. 서비스 계층(`DebriefTopic`)은 `style` 값만 들고 있고
//     SwiftUI 를 모른다.
//

import SwiftUI

struct DebriefVisualView: View {

    let visual: DebriefVisual

    var body: some View {
        if !visual.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                if !visual.speedSigns.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(visual.speedSigns) { SpeedSignView(spec: $0) }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !visual.badgeRows.isEmpty {
                    VStack(spacing: 18) {
                        ForEach(visual.badgeRows) { BadgeRowView(spec: $0) }
                    }
                }

                if !visual.lineRows.isEmpty {
                    VStack(spacing: 16) {
                        ForEach(visual.lineRows) { LineRowView(spec: $0) }
                    }
                }
            }
            .debriefCardStyle()
        }
    }
}

// MARK: - 원형 속도 표지판

/// 한국 규제표지 실제 배색을 따른다. 표지판은 바깥에서 보는 것과 같아야 의미가 있다.
private struct SpeedSignView: View {

    let spec: SpeedSignSpec

    private var ringColor: Color {
        switch spec.style {
        case .maximum: return Color(red: 214 / 255, green: 40 / 255, blue: 40 / 255)
        case .minimum: return Color(red: 0, green: 82 / 255, blue: 212 / 255)
        case .schoolZone: return Color(red: 245 / 255, green: 196 / 255, blue: 0)
        }
    }

    /// 최저속도 표지판만 바탕이 파랗고 숫자가 희다.
    private var isFilled: Bool { spec.style == .minimum }

    var body: some View {
        VStack(spacing: 10) {
            Text("\(spec.speedKPH)")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(isFilled ? .white : Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255))
                .frame(width: 62, height: 62)
                .background(isFilled ? ringColor : .white, in: .circle)
                .overlay(Circle().stroke(ringColor, lineWidth: isFilled ? 0 : 6))

            Text(spec.caption)
                .font(.system(size: 13))
                .foregroundStyle(DebriefStyle.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spec.caption) \(spec.speedKPH) kilometres per hour")
    }
}

// MARK: - 배지 + 설명

private struct BadgeRowView: View {

    let spec: BadgeRowSpec

    private var badgeBackground: Color {
        switch spec.style {
        case .highlighted: return Color(red: 0, green: 82 / 255, blue: 212 / 255)
        case .neutral: return DebriefStyle.row
        case .informational: return DebriefStyle.positive.opacity(0.18)
        }
    }

    private var badgeForeground: Color {
        switch spec.style {
        case .highlighted: return .white
        case .neutral: return DebriefStyle.primaryText
        case .informational: return DebriefStyle.positive
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(spec.badge)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(badgeForeground)
                .frame(width: 78, height: 32)
                .background(badgeBackground, in: RoundedRectangle(cornerRadius: 8))

            Text(spec.text)
                .font(.system(size: 15))
                .foregroundStyle(DebriefStyle.primaryText.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 노면선 견본 + 설명

private struct LineRowView: View {

    let spec: LineRowSpec

    private static let yellow = Color(red: 247 / 255, green: 181 / 255, blue: 56 / 255)
    private static let red = Color(red: 226 / 255, green: 66 / 255, blue: 66 / 255)

    var body: some View {
        HStack(spacing: 16) {
            swatch
                .frame(width: 52, height: 26)

            Text(spec.text)
                .font(.system(size: 15))
                .foregroundStyle(DebriefStyle.primaryText.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// 실제 노면표시처럼 선의 색·개수·실선 여부로 규칙을 나타낸다. 이 그림이 곧 설명이다.
    @ViewBuilder
    private var swatch: some View {
        switch spec.pattern {
        case .white:
            line(color: .white)
        case .dashedYellow:
            line(color: Self.yellow, dashed: true)
        case .solidYellow:
            line(color: Self.yellow)
        case .doubleYellow:
            VStack(spacing: 5) {
                line(color: Self.yellow)
                line(color: Self.yellow)
            }
        case .red:
            VStack(spacing: 5) {
                line(color: Self.red)
                line(color: Self.red)
            }
        }
    }

    private func line(color: Color, dashed: Bool = false) -> some View {
        Rectangle()
            .fill(dashed ? AnyShapeStyle(dashPattern(color)) : AnyShapeStyle(color))
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 1))
    }

    private func dashPattern(_ color: Color) -> some ShapeStyle {
        LinearGradient(stops: [
            .init(color: color, location: 0), .init(color: color, location: 0.32),
            .init(color: .clear, location: 0.32), .init(color: .clear, location: 0.5),
            .init(color: color, location: 0.5), .init(color: color, location: 0.82),
            .init(color: .clear, location: 0.82), .init(color: .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }
}

#Preview("표지판") {
    DebriefVisualView(visual: TrafficRuleRepository.speedLimitChange.visual)
        .padding()
        .frame(maxHeight: .infinity)
        .debriefBackground()
        .preferredColorScheme(.dark)
}

#Preview("톨게이트 차로") {
    DebriefVisualView(visual: TrafficRuleRepository.tollGate.visual)
        .padding()
        .frame(maxHeight: .infinity)
        .debriefBackground()
        .preferredColorScheme(.dark)
}

#Preview("노면선") {
    DebriefVisualView(visual: TrafficRuleRepository.noParkingZone.visual)
        .padding()
        .frame(maxHeight: .infinity)
        .debriefBackground()
        .preferredColorScheme(.dark)
}

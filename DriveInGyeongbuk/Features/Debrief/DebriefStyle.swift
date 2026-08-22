//
//  DebriefStyle.swift
//  DriveInGyeongbuk
//
//  Debrief 화면들이 같이 쓰는 색·타이포·카드 모양.
//
//  피그마 시안은 순검정 바탕에 형광 그린이었는데, 이 앱의 나머지 화면은 네이비 계열이다
//  (`RouteSummaryCard.routeCardStyle`, `MapHomeView.driveStatusBar` 참고).
//  Debrief 만 다른 앱처럼 보이면 안 되므로 **시안의 구조는 가져오고 색은 기존 팔레트로**
//  옮겼다. 그린은 시안처럼 넓게 쓰지 않고 "주행 완료" 같은 상태 표시에만 남겼다.
//
//  값을 여기 모아 둔 이유는 화면이 늘어날 때 색이 각자 흩어지지 않게 하려는 것이다.
//

import SwiftUI

enum DebriefStyle {

    // MARK: 색

    /// 화면 바탕. 카드(`card`)보다 어두워야 카드가 떠 보인다.
    static let background = Color(red: 8 / 255, green: 14 / 255, blue: 31 / 255)
    /// 카드 바탕. `routeCardStyle` 과 같은 값이다.
    static let card = Color(red: 19 / 255, green: 31 / 255, blue: 61 / 255)
    /// 카드 안의 줄. `RouteSummaryCard.metricCard` 와 같은 값이다.
    static let row = Color(red: 34 / 255, green: 42 / 255, blue: 61 / 255)

    /// 본문.
    static let primaryText = Color(red: 218 / 255, green: 226 / 255, blue: 253 / 255)
    /// 보조 문구.
    static let secondaryText = Color(red: 179 / 255, green: 197 / 255, blue: 1).opacity(0.65)
    /// 강조 숫자·링크.
    static let accent = Color(red: 179 / 255, green: 197 / 255, blue: 1)
    /// 선택·완료 상태.
    static let positive = Color(red: 0, green: 230 / 255, blue: 118 / 255)
    /// 눈여겨볼 것. 시안의 Tip 카드 색을 네이비에 맞게 낮춘 값이다.
    static let caution = Color(red: 1, green: 196 / 255, blue: 107 / 255)

    static let hairline = Color.white.opacity(0.1)

    // MARK: 치수

    static let horizontalMargin: CGFloat = 20
    static let cornerRadius: CGFloat = 16

    // MARK: 타이포

    /// 섹션 위의 작은 대문자 라벨 ("ON TODAY'S DRIVE").
    static func eyebrow(_ text: String, color: Color = positive) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

// MARK: - 카드

extension View {

    /// Debrief 화면의 기본 카드.
    func debriefCardStyle(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DebriefStyle.card, in: RoundedRectangle(cornerRadius: DebriefStyle.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: DebriefStyle.cornerRadius)
                .stroke(DebriefStyle.hairline))
    }

    /// Debrief 화면의 바탕. 스크롤 여부와 상관없이 화면 전체를 덮는다.
    func debriefBackground() -> some View {
        self.background(DebriefStyle.background.ignoresSafeArea())
    }
}

// MARK: - Tip 카드

/// 화면 아래 고정되는 한 마디. 시안의 "REMEMBER / IF YOU'RE UNSURE" 자리.
///
/// 시안은 올리브색 박스였지만, 여기서는 카드 색을 그대로 두고 **왼쪽 세로선과 라벨에만**
/// 경고색을 준다. 네이비 화면에서 박스 전체를 물들이면 그 부분만 붕 뜬다.
struct DebriefTipCard: View {

    let label: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DebriefStyle.eyebrow(label, color: DebriefStyle.caution)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(DebriefStyle.primaryText.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.leading, 24)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebriefStyle.card, in: RoundedRectangle(cornerRadius: DebriefStyle.cornerRadius))
        // 세로선은 `overlay` 로 얹는다.
        //
        // HStack 안에 넣으면 안 된다. Shape 는 세로로 greedy 라서 `frame(width:)` 만 주면
        // 높이가 무한정 늘어나고, 그 HStack 을 `safeAreaInset` 에 넣는 순간 카드가 화면을
        // 통째로 덮어 버린다. overlay 는 배경(=텍스트 높이)에 맞춰 잘리므로 그 일이 없다.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DebriefStyle.caution)
                .frame(width: 3)
                .padding(.vertical, 14)
                .padding(.leading, 12)
        }
        .overlay(RoundedRectangle(cornerRadius: DebriefStyle.cornerRadius)
            .stroke(DebriefStyle.hairline))
    }
}

#Preview {
    VStack(spacing: 16) {
        DebriefTipCard(label: "Remember",
                       message: "School zones are 30 km/h around the clock, not only during school hours.")
        DebriefTipCard(label: "If you're unsure",
                       message: "Check whether anything went unpaid at ex.co.kr, or call 1588-2504.")
    }
    .padding()
    .frame(maxHeight: .infinity)
    .debriefBackground()
    .preferredColorScheme(.dark)
}

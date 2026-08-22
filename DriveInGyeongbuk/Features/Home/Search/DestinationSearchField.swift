//
//  DestinationSearchField.swift
//  DriveInGyeongbuk
//
//  홈과 검색 화면이 공유하는 검색 캡슐.
//

import SwiftUI

struct DestinationSearchField<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 17)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            // 지도와 단색 검색 배경에서 같은 농도로 보이도록 공통 바탕과 테두리를 고정한다.
            .background(Color.black.opacity(0.18), in: Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

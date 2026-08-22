//
//  HomeView.swift
//  DriveInGyeongbuk
//
//  앱의 루트. 피그마 시안의 하단 탭바(Map / Trip / Settings)를 담당한다.
//
//  탭바는 직접 그리지 않는다. iOS 26 의 `TabView` 가 시안과 같은 글래스 알약
//  모양으로 알아서 그려 주고, 지도는 그 아래까지 꽉 차게 깔린다.
//

import SwiftUI

struct HomeView: View {

    /// 시안의 선택 색(#4F79FF).
    private static let accent = Color(red: 79 / 255, green: 121 / 255, blue: 255 / 255)

    private enum HomeTab: Hashable {
        case map, trip, settings
    }

    @State private var selection: HomeTab = .map

    var body: some View {
        TabView(selection: $selection) {
            Tab("Map", systemImage: "map.fill", value: .map) {
                MapHomeView()
            }

            Tab("Trip", systemImage: "bag.fill", value: .trip) {
                TripView()
            }

            Tab("Settings", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
        }
        .tint(Self.accent)
        // 시안이 다크 테마 기준이라 화면 전체를 다크로 고정한다.
        // 라이트 테마도 지원하려면 이 한 줄만 지우면 된다 (지도는 이미 colorScheme 을 따라간다).
        .preferredColorScheme(.dark)
    }
}

#Preview {
    HomeView()
}

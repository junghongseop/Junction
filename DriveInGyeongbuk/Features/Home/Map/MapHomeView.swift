//
//  MapHomeView.swift
//  DriveInGyeongbuk
//
//  앱의 첫 화면. 현재 위치를 중심으로 지도를 띄우고, 그 위에 목적지 검색 필드와
//  안내 버튼을 얹는다. (피그마 "홈 화면" 시안)
//
//  글래스 표현은 직접 그리지 않고 iOS 26 기본 컴포넌트만 쓴다.
//    검색 필드 · 상태 문구 → `.glassEffect(_:in:)`
//    안내 버튼           → `.buttonStyle(.glass)` + `.buttonBorderShape(.circle)`
//    하단 탭바           → `TabView` 기본 형태 (HomeView 참고)
//  여러 글래스를 한 덩어리로 묶어 반응시키기 위해 `GlassEffectContainer` 로 감쌌다.
//

import NMapsMap
import SwiftUI

struct MapHomeView: View {

    @StateObject private var viewModel = MapHomeViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var isShowingInfo = false

    /// 시안 값. 지도 로고가 하단 탭바에 가리지 않도록 띄우는 여백이기도 하다.
    private let horizontalMargin: CGFloat = 16
    private let stackSpacing: CGFloat = 24

    var body: some View {
        ZStack(alignment: .top) {
            NaverMapView(controller: viewModel.map,
                         positionMode: viewModel.isTrackingLocation ? .direction : .disabled,
                         isNightMode: colorScheme == .dark,
                         logoMargin: UIEdgeInsets(top: 0, left: 12, bottom: 12, right: 0))
                .ignoresSafeArea()

            topControls
        }
        .sheet(isPresented: $isShowingInfo) { AppInfoView() }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    // MARK: - 상단 오버레이

    private var topControls: some View {
        GlassEffectContainer(spacing: stackSpacing) {
            VStack(alignment: .trailing, spacing: stackSpacing) {
                searchField

                if let statusMessage = viewModel.statusMessage {
                    locationStatus(statusMessage)
                }

                infoButton
            }
            .padding(.horizontal, horizontalMargin)
            .padding(.top, 8)
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            // TODO: 제출 시 NaverGeocodingService 로 목적지를 찾아 경로 화면으로 넘긴다.
            //       (목적지 검색 결과 시안이 아직 없어 입력만 받아 둔다)
            TextField("Search destination", text: $viewModel.searchText)
                .font(.system(size: 16, weight: .medium))
                .tracking(0.4)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
        }
        .padding(.horizontal, 17)
        .frame(height: 56)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func locationStatus(_ message: String) -> some View {
        Label(message, systemImage: "location.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .capsule)
    }

    private var infoButton: some View {
        Button {
            isShowingInfo = true
        } label: {
            // 20pt 아이콘 + 상하좌우 11pt = 42pt 원형 버튼.
            // 시안은 56pt 지만 실기기에서 지도를 가릴 만큼 커 보여서 줄였다.
            // 42pt 는 최소 터치 영역(44pt)에 맞닿는 크기라 이보다 더 줄이면 누르기 어려워진다.
            Image(systemName: "info")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 20, height: 20)
                .padding(11)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("About this app")
    }
}

#Preview {
    MapHomeView()
}

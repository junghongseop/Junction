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

    private enum DestinationRoute: Hashable {
        case search
        case routePreview
    }

    @StateObject private var viewModel = MapHomeViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var isShowingInfo = false
    @State private var navigationPath: [DestinationRoute] = []

    /// 시안 값. 지도 로고가 하단 탭바에 가리지 않도록 띄우는 여백이기도 하다.
    private let horizontalMargin: CGFloat = 16
    private let stackSpacing: CGFloat = 24

    var body: some View {
        NavigationStack(path: $navigationPath) {
            homeMap
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: DestinationRoute.self) { route in
                    switch route {
                    case .search:
                        SearchView(initialQuery: viewModel.searchText) { location in
                            viewModel.prepareDestination(location)
                            // 검색 화면을 스택에 남겨 경로 화면의 기본 뒤로가기가 검색으로 돌아가게 한다.
                            navigationPath.append(.routePreview)
                        }
                    case .routePreview:
                        routePreview
                    }
                }
        }
        .sheet(isPresented: $isShowingInfo) { AppInfoView() }
        .onChange(of: navigationPath) { _, newPath in
            guard viewModel.destination != nil else { return }
            if newPath.isEmpty {
                viewModel.clearDestination()
            } else if !newPath.contains(.routePreview) {
                // 경로 화면 → 검색 화면에서는 검색 상태를 보존한다.
                viewModel.leaveRoutePreview()
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var homeMap: some View {
        ZStack(alignment: .top) {
            NaverMapView(controller: viewModel.map,
                         positionMode: viewModel.isTrackingLocation ? .direction : .disabled,
                         isNightMode: colorScheme == .dark,
                         logoMargin: UIEdgeInsets(top: 0, left: 12, bottom: 12, right: 0))
                .ignoresSafeArea()

            topControls
        }
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
        DestinationSearchField {
            Button {
                navigationPath.append(.search)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))

                    Text(viewModel.searchText.isEmpty ? "Search destination" : viewModel.searchText)
                        .font(.system(size: 16, weight: .medium))
                        .tracking(0.4)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search destination")
        }
    }

    // MARK: - 경로 미리보기

    private var routePreview: some View {
        ZStack {
            NaverMapView(controller: viewModel.routeMap,
                         positionMode: viewModel.isDriving ? .direction : .disabled,
                         isNightMode: colorScheme == .dark,
                         logoMargin: UIEdgeInsets(top: 0, left: 12, bottom: 390, right: 0))
                .ignoresSafeArea()

            VStack {
                Spacer()
                routeCard
                    .padding(.horizontal, 18.5)
                    .padding(.bottom, 40)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task(id: viewModel.destination?.id) {
            guard viewModel.route == nil, !viewModel.isRouteLoading else { return }
            await viewModel.retryRoute()
        }
    }

    @ViewBuilder
    private var routeCard: some View {
        if viewModel.isRouteLoading {
            ProgressView("Finding the best route…")
                .frame(maxWidth: .infinity, minHeight: 180)
                .routeCardStyle()
        } else if let errorMessage = viewModel.routeErrorMessage {
            ContentUnavailableView {
                Label("Route unavailable", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try again") { Task { await viewModel.retryRoute() } }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .routeCardStyle()
        } else if let route = viewModel.route, let destination = viewModel.destination {
            RouteSummaryCard(destination: destination,
                             route: route,
                             safeRoute: viewModel.safeRoute,
                             onStart: viewModel.startDriving)
        }
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

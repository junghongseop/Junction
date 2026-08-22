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
    @State private var isVoiceGuidanceMuted = false
    @State private var isShowingDriveSettings = false

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
        // 주행이 끝나면 Debrief 를 덮어 씌운다.
        // `navigationPath` 대신 별도 표현으로 띄우는 이유: 아래 `onChange(of: navigationPath)` 가
        // 경로가 비면 목적지를 지우게 되어 있어서, 여기에 화면을 하나 더 밀어 넣으면 서로 싸운다.
        .fullScreenCover(item: finishedDriveBinding) { recording in
            DebriefView(recording: recording) { viewModel.dismissDebrief() }
        }
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

    /// `@Published private(set)` 은 그대로 바인딩할 수 없어서 읽기/닫기만 이어 준다.
    private var finishedDriveBinding: Binding<DriveRecording?> {
        Binding(get: { viewModel.finishedDrive },
                set: { if $0 == nil { viewModel.dismissDebrief() } })
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
                         navigationZoom: viewModel.isDriving ? 18.5 : nil,
                         isNightMode: colorScheme == .dark,
                         logoMargin: UIEdgeInsets(top: 0, left: 12, bottom: 390, right: 0))
                .ignoresSafeArea()

            if viewModel.isDriving {
                drivingOverlay
            } else {
                VStack {
                    Spacer()
                    routeCard
                        .padding(.horizontal, 18.5)
                        .padding(.bottom, 40)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(viewModel.isDriving ? .hidden : .visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                             selectedOption: viewModel.selectedRouteOption,
                             onSelect: viewModel.selectRoute,
                             onStart: viewModel.startDriving)
        }
    }

    private var drivingOverlay: some View {
        VStack(spacing: 0) {
            maneuverCard
                .padding(.horizontal, 16)
                .padding(.top, 20)

            Spacer()

            HStack(alignment: .bottom) {
                VStack(spacing: 16) {
                    driveCircleButton(systemName: isVoiceGuidanceMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                        isVoiceGuidanceMuted.toggle()
                    }
                    driveCircleButton(systemName: "gearshape.fill") {
                        isShowingDriveSettings.toggle()
                    }
                    .popover(isPresented: $isShowingDriveSettings) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Drive settings").font(.headline)
                            Toggle("Voice guidance", isOn: Binding(
                                get: { !isVoiceGuidanceMuted },
                                set: { isVoiceGuidanceMuted = !$0 }
                            ))
                        }
                        .padding()
                        .presentationCompactAdaptation(.popover)
                    }
                }

                Spacer()

                Button("Finish", action: viewModel.finishDriving)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 105 / 255, green: 0, blue: 5 / 255))
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(Color(red: 1, green: 180 / 255, blue: 171 / 255), in: .capsule)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)

            driveStatusBar
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var maneuverCard: some View {
        let step = viewModel.selectedRoute?.steps.first { $0.kind != .departure }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: step?.kind.symbolName ?? "arrow.up")
                    .font(.system(size: 38, weight: .bold))
                    .frame(width: 64, height: 64)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(step?.distanceDescription ?? "Start")
                        .font(.system(size: 40, weight: .heavy))
                    Text(step?.instructionTitle ?? "Follow the route")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color(red: 201 / 255, green: 212 / 255, blue: 1))
                        .lineLimit(1)
                }
            }

            Text(step?.roadName ?? "Route guidance")
                .font(.system(size: 32, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(red: 0, green: 82 / 255, blue: 212 / 255),
                    in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
    }

    private var driveStatusBar: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(estimatedArrival, style: .time)
                .font(.system(size: 30, weight: .bold))
            Text("ETA").font(.system(size: 18, weight: .medium))
            Spacer()
            Text(viewModel.selectedRoute?.distanceValue ?? "–")
                .font(.system(size: 30, weight: .bold))
            Text(viewModel.selectedRoute?.distanceUnit ?? "km")
                .font(.system(size: 18, weight: .medium))
        }
        .foregroundStyle(Color(red: 179 / 255, green: 197 / 255, blue: 1))
        .padding(.horizontal, 16)
        .frame(height: 80)
        .background(Color(red: 17 / 255, green: 33 / 255, blue: 72 / 255).opacity(0.88),
                    in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1)))
    }

    private var estimatedArrival: Date {
        Date().addingTimeInterval(TimeInterval(viewModel.selectedRoute?.duration ?? 0))
    }

    private func driveCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial, in: .circle)
                .overlay(Circle().stroke(Color.white.opacity(0.2)))
        }
        .buttonStyle(.plain)
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

private extension RouteStep {
    var distanceDescription: String {
        distance >= 1000
            ? String(format: "%.1fkm", Double(distance) / 1000)
            : "\(max(0, distance))m"
    }

    var instructionTitle: String {
        switch kind {
        case .turnLeft: return "Turn left"
        case .turnRight: return "Turn right"
        case .uTurn: return "Make a U-turn"
        case .keepLeft: return "Keep left"
        case .keepRight: return "Keep right"
        case .tollGate: return "Use the Hi-Pass lane"
        case .highwayEntrance: return "Enter the highway"
        case .highwayExit: return "Take the exit"
        case .roundabout: return "Enter the roundabout"
        case .destination: return "Arrive at destination"
        default: return "Continue straight"
        }
    }

    var roadName: String {
        guard let destinationName = quotedDestinationName else {
            return kind == .destination ? "Destination ahead" : "Toward the next road"
        }
        let romanized = destinationName
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)
            ?? destinationName
        return "Toward \(romanized)"
    }

    private var quotedDestinationName: String? {
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

#Preview {
    MapHomeView()
}

//
//  SpeedLimitTestView.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] Services/SpeedLimit 검증 화면.
//
//  이 화면에서 확인할 수 있는 것
//    1. 번들 SQLite 가 열리고 R-tree 공간 검색이 되는가        → SQLiteSpeedLimitDataSource
//    2. EPSG:5179 ↔ WGS84 변환이 맞는가 (지도 위 스냅 위치)     → KoreaCoordinateConverter
//    3. GSL1 형상 파싱과 점-폴리라인 매칭이 되는가             → SpeedLimitLink / PolylineMath
//    4. 경로가 제한속도 구간으로 잘 쪼개지는가                 → SpeedLimitService.prepare
//    5. 초과 경고 / 감속 예고가 뜨는가                        → SpeedLimitService.alert
//
//  1~3 은 네이버 API 키 없이도 확인할 수 있다. 4~5 는 경로 탐색이 필요해 REST 키가 있어야 한다.
//  제품 UI 가 아니라 서비스 계층 확인용이므로 디자인은 최소한만 했다.
//

import SwiftUI

struct SpeedLimitTestView: View {

    /// 모달로 띄웠을 때 닫기 버튼을 노출하기 위한 콜백.
    var onClose: (() -> Void)?

    @StateObject private var viewModel = SpeedLimitTestViewModel()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SpeedLimitMapPane(controller: viewModel.map)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let setupError = viewModel.setupError {
                            banner(setupError, systemImage: "xmark.octagon", tint: .red)
                        }
                        if let warning = viewModel.credentialWarning {
                            banner(warning, systemImage: "exclamationmark.triangle", tint: .orange)
                        }

                        lookupSection
                        statusSection

                        if let match = viewModel.nearestMatch {
                            nearestMatchSection(match)
                        }
                        if !viewModel.nearbyLinks.isEmpty {
                            nearbyLinksSection
                        }

                        Divider()

                        routeSection
                        if !viewModel.segments.isEmpty {
                            simulationSection
                            segmentsSection
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("SpeedLimit 테스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기", action: onClose)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("초기화", action: viewModel.reset)
                }
            }
        }
    }

    // MARK: - 1. 좌표 조회

    private var lookupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("좌표로 제한속도 조회", subtitle: "번들 DB만 사용 · 지도를 탭해도 된다")

            HStack(spacing: 8) {
                LabeledField(title: "위도", text: $viewModel.latitudeText)
                LabeledField(title: "경도", text: $viewModel.longitudeText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("검색 반경 \(Int(viewModel.radiusMeters))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.radiusMeters, in: 50...2000, step: 50)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpeedLimitTestViewModel.presets) { preset in
                        Button(preset.name) { viewModel.use(preset) }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            }

            Button {
                Task { await viewModel.lookupAroundTypedCoordinate() }
            } label: {
                Label("주변 도로 조회", systemImage: "location.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
    }

    private func nearestMatchSection(_ match: SpeedLimitMatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("가장 가까운 도로", subtitle: "현재 위치를 이 링크에 스냅한다")

            HStack(alignment: .center, spacing: 14) {
                SpeedLimitBadge(limitKPH: match.limitKPH)

                VStack(alignment: .leading, spacing: 3) {
                    Text(match.link.displayName).font(.headline)
                    Text("\(match.roadRank.koreanTitle) · \(match.roadRank.englishTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "수직거리 %.1fm · 링크 길이 %.0fm · ID %lld",
                                match.lateralDistanceMeters, match.link.lengthMeters, match.link.linkID))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !match.link.isReliableLimit {
                        Text("이면도로 값(30km/h 미만)이라 초과 경고에는 쓰지 않는다")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        }
    }

    private var nearbyLinksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("주변 링크 \(viewModel.nearbyLinks.count)개", subtitle: "가까운 순 · 최대 20개 표시")

            ForEach(viewModel.nearbyLinks.prefix(20)) { link in
                HStack(spacing: 10) {
                    Text("\(link.limitKPH)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(link.displayName).font(.caption)
                        Text("\(link.roadRank.koreanTitle) · \(Int(link.lengthMeters))m")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 2. 경로 제한속도

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("경로 제한속도 구간", subtitle: "Directions 5 경로를 제한속도별로 쪼갠다 · REST 키 필요")

            LabeledField(title: "출발지", text: $viewModel.startQuery)
            LabeledField(title: "도착지", text: $viewModel.goalQuery)

            Button {
                Task { await viewModel.findRouteAndPrepare() }
            } label: {
                Label("경로 탐색 후 제한속도 매칭", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading || !AppConfig.hasNaverMapsRESTCredentials)
        }
    }

    private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("주행 시뮬레이션", subtitle: "경로 위를 움직이며 안내가 뜨는지 본다")

            VStack(alignment: .leading, spacing: 4) {
                Text("경로 진행 \(Int(viewModel.simulationProgress * 100))%")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $viewModel.simulationProgress, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("현재 속도 \(Int(viewModel.simulatedSpeedKPH))km/h")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $viewModel.simulatedSpeedKPH, in: 0...140, step: 5)
            }

            HStack(spacing: 14) {
                if let limit = viewModel.simulatedLimitKPH {
                    SpeedLimitBadge(limitKPH: limit)
                } else {
                    VStack {
                        Image(systemName: "questionmark")
                        Text("정보 없음").font(.caption2)
                    }
                    .frame(width: 62, height: 62)
                    .background(.quaternary, in: .circle)
                }

                if let alert = viewModel.simulatedAlert {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.koreanMessage)
                            .font(.subheadline.bold())
                            .foregroundStyle(alert.severity == .exceeding ? .red : .orange)
                        Text(alert.englishMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let roadName = alert.roadName {
                            Text(roadName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("안내할 내용 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
        }
    }

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("제한속도 구간 \(viewModel.segments.count)개", subtitle: "경로 진행순")

            ForEach(viewModel.segments) { segment in
                HStack(spacing: 10) {
                    Text(segment.limitKPH.map { "\($0)" } ?? "–")
                        .font(.caption.bold().monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(segment.limitKPH == nil ? .secondary : .primary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(segment.displayName).font(.caption)
                        Text(String(format: "%.1fkm 지점부터 %.0fm",
                                    segment.distanceFromStartMeters / 1000, segment.lengthMeters))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 공통

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            }
            if let status = viewModel.statusMessage {
                banner(status, systemImage: "info.circle", tint: .blue)
            }
            if let error = viewModel.errorMessage {
                banner(error, systemImage: "exclamationmark.triangle.fill", tint: .red)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func banner(_ message: String, systemImage: String, tint: Color) -> some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

// MARK: - 구성 요소

/// 한국 제한속도 표지판 모양의 배지.
private struct SpeedLimitBadge: View {
    var limitKPH: Int

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().stroke(.red, lineWidth: 6)
            Text("\(limitKPH)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.black)
        }
        .frame(width: 62, height: 62)
    }
}

private struct LabeledField: View {
    var title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}

/// 지도와 지도 자체의 상태(로딩/인증 실패)를 함께 보여 준다.
private struct SpeedLimitMapPane: View {

    @ObservedObject var controller: NaverMapWebController

    var body: some View {
        ZStack {
            NaverMapWebView(controller: controller)

            if !controller.isReady && controller.mapError == nil {
                ProgressView("지도를 불러오는 중…")
                    .padding(12)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }

            if let error = controller.mapError {
                VStack(spacing: 8) {
                    Image(systemName: "map.circle").font(.largeTitle)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
                .padding(24)
            }
        }
    }
}

#Preview {
    SpeedLimitTestView()
}

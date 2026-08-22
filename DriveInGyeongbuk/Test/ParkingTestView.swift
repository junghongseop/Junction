//
//  ParkingTestView.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] Services/Parking + Services/Enforcement 검증 화면.
//
//  이 화면에서 확인할 수 있는 것
//    1. 백엔드에서 주차장 목록이 오는가                    → ParkingAPIClient
//    2. 거리순 정렬 · 도보 시간 계산이 되는가              → ParkingService.suggestions
//    3. 주정차 금지구간과 도로 경로(path)가 오는가         → EnforcementAPIClient
//    4. 요일·시간표로 지금 단속 중인지 판정되는가          → RestrictionSchedule.status(at:)
//    5. 현재 위치 기준 경고가 뜨는가                       → EnforcementService.warnings
//
//  1~5 는 네이버 API 키 없이도 확인할 수 있다. 지도 표시와 주소 검색만 키가 필요하다.
//  제품 UI 가 아니라 서비스 계층 확인용이므로 디자인은 최소한만 했다.
//

import SwiftUI

struct ParkingTestView: View {

    /// 모달로 띄웠을 때 닫기 버튼을 노출하기 위한 콜백.
    var onClose: (() -> Void)?

    @StateObject private var viewModel = ParkingTestViewModel()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ParkingMapPane(controller: viewModel.map)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let warning = viewModel.credentialWarning {
                            banner(warning, systemImage: "exclamationmark.triangle", tint: .orange)
                        }

                        lookupSection
                        statusSection

                        if !viewModel.zones.isEmpty {
                            Divider()
                            simulationSection
                            zonesSection
                        }

                        if !viewModel.suggestions.isEmpty {
                            Divider()
                            parkingSection
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Parking 테스트")
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

    // MARK: - 1. 목적지 조회

    private var lookupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("목적지 주변 조회",
                         subtitle: "백엔드만 사용 · 지도를 탭해도 된다 · 서버 검색 반경은 2km 고정")

            HStack(spacing: 8) {
                LabeledField(title: "위도", text: $viewModel.latitudeText)
                LabeledField(title: "경도", text: $viewModel.longitudeText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("조회 반경 \(Int(viewModel.radiusMeters))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.radiusMeters, in: 100...2000, step: 100)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ParkingTestViewModel.presets) { preset in
                        Button(preset.name) { viewModel.use(preset) }
                            .buttonStyle(.bordered)
                            .font(.caption)
                    }
                }
            }

            Button {
                Task { await viewModel.lookupAroundTypedCoordinate() }
            } label: {
                Label("이 좌표로 조회", systemImage: "parkingsign.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)

            LabeledField(title: "주소로 목적지 찾기", text: $viewModel.destinationQuery)

            Button {
                Task { await viewModel.lookupByAddress() }
            } label: {
                Label("주소로 조회", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading || !AppConfig.hasNaverMapsRESTCredentials)

            if viewModel.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 2. 경고 시뮬레이션

    private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("주정차 경고",
                         subtitle: "첫 번째 금지구간 위를 따라가며 \(viewModel.warningRadiusMeters)m 이내 경고를 만든다")

            VStack(alignment: .leading, spacing: 4) {
                Text("구간 진행 \(Int(viewModel.simulationProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.simulationProgress, in: 0...1)
            }

            if let coordinate = viewModel.simulatedCoordinate {
                Text("현재 위치 \(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if viewModel.warnings.isEmpty {
                banner("이 위치 주변에는 주정차 금지구간이 없습니다.",
                       systemImage: "checkmark.circle", tint: .green)
            } else {
                ForEach(viewModel.warnings) { warning in
                    WarningCard(warning: warning)
                }
            }
        }
    }

    // MARK: - 3. 금지구간 목록

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("주정차 금지구간 \(viewModel.zones.count)곳",
                         subtitle: "빨강 = 조회 시점에 단속 중 · 주황 = 지금은 단속 시간이 아님")

            ForEach(viewModel.zones) { zone in
                ZoneRow(zone: zone)
            }
        }
    }

    // MARK: - 4. 주차장 목록

    private var parkingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("주차장 \(viewModel.suggestions.count)곳",
                         subtitle: "목적지에서 가까운 순 · 도보 시간은 직선거리 기반 추정값")

            ForEach(viewModel.suggestions) { suggestion in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "parkingsign.square.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.lot.name).font(.subheadline)
                        Text(String(format: "%.5f, %.5f",
                                    suggestion.lot.coordinate.latitude,
                                    suggestion.lot.coordinate.longitude))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(suggestion.distanceDescription)
                            .font(.caption.monospacedDigit())
                        if let minutes = suggestion.walkingMinutes {
                            Label("\(minutes)분", systemImage: "figure.walk")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    // MARK: - 공통

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

private struct WarningCard: View {
    var warning: EnforcementWarning

    private var tint: Color {
        switch warning.status {
        case .restricted:         return .red
        case .temporarilyAllowed: return .orange
        case .inactive:           return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(warning.status.koreanName, systemImage: warning.isCurrentlyEnforced
                      ? "exclamationmark.octagon.fill" : "clock")
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Spacer()
                Text(warning.distanceDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(warning.koreanMessage).font(.subheadline)
            Text(warning.localizedMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }
}

private struct ZoneRow: View {
    var zone: EnforcementZone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(zone.roadName).font(.subheadline.bold())
                Text(zone.koreanTypeName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: .capsule)
                Spacer()
                Text("\(Int(zone.distanceFromDestinationMeters))m")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(zone.detailLocation)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(zone.serverStatus.koreanName)
                    .font(.caption2.bold())
                    .foregroundStyle(zone.serverStatus.prohibitsParkingNow ? .red : .secondary)
                Text("·").foregroundStyle(.secondary)
                Text(zone.schedule.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.secondary)
                Text("좌표 \(zone.path.count)개")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        Divider()
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
private struct ParkingMapPane: View {

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
    ParkingTestView()
}

//
//  NaverMapsTestView.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] Services/NaverMaps 검증 화면.
//
//  이 화면에서 확인할 수 있는 것
//    1. 네이버 지도가 실제로 뜨는가                     → NaverMapWebView
//    2. 주소 → 좌표 변환이 되는가                       → NaverGeocodingService.geocode
//    3. 지도를 탭하면 좌표 → 주소 변환이 되는가          → NaverGeocodingService.reverseGeocode
//    4. 경로가 탐색되고 폴리라인이 그려지는가            → NaverDirectionsService.route
//    5. 턴바이턴 안내/구간/요금 파싱이 맞는가            → DrivingRoute (NaverMapDTO)
//
//  제품 UI 가 아니라 서비스 계층 확인용이므로 디자인은 최소한만 했다.
//

import SwiftUI

struct NaverMapsTestView: View {

    /// 모달로 띄웠을 때 닫기 버튼을 노출하기 위한 콜백.
    var onClose: (() -> Void)?

    @StateObject private var viewModel = NaverMapsTestViewModel()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapPane(controller: viewModel.map)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let warning = viewModel.credentialWarning {
                            banner(warning, systemImage: "exclamationmark.triangle", tint: .orange)
                        }
                        searchSection
                        routeSection
                        statusSection
                        if let address = viewModel.tappedAddress {
                            tappedAddressSection(address)
                        }
                        if !viewModel.geocodeResults.isEmpty {
                            geocodeResultsSection
                        }
                        if !viewModel.locationResults.isEmpty {
                            locationResultsSection
                        }
                        if let route = viewModel.route {
                            routeSummarySection(route)
                            stepsSection(route)
                            sectionsSection(route)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("NaverMaps 테스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("닫기", action: onClose)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("초기화", role: .destructive) { viewModel.reset() }
                }
            }
        }
    }

    // MARK: - 주소 검색

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("1. 출발지 주소 · 도착지 장소 검색")

            queryField(title: "출발지",
                       text: $viewModel.startQuery,
                       place: viewModel.startPlace,
                       endpoint: .start)

            queryField(title: "도착지",
                       text: $viewModel.goalQuery,
                       place: viewModel.goalPlace,
                       endpoint: .goal)

            Text("도착지는 네이버 지역 검색 API로 업체·기관명을 검색합니다. (예: 불국사, 경주역)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("지도를 탭하면 그 지점의 주소를 역지오코딩합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func queryField(title: String,
                            text: Binding<String>,
                            place: GeocodedPlace?,
                            endpoint: NaverMapsTestViewModel.Endpoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await viewModel.search(endpoint) } }

                Button("검색") { Task { await viewModel.search(endpoint) } }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
            }

            if let place {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.displayAddress).font(.caption).bold()
                    if !place.englishAddress.isEmpty {
                        Text(place.englishAddress)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(place.coordinate.apiQueryValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 경로 탐색

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("2. 경로 탐색 (Directions)")

            Picker("탐색 옵션", selection: $viewModel.option) {
                ForEach(RouteOption.allCases) { option in
                    Text(option.koreanTitle).tag(option)
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.findRoute() }
                } label: {
                    Label("경로 탐색", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)

                Button("전체 보기") { viewModel.showWholeRoute() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.route == nil)
            }
        }
    }

    // MARK: - 상태

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.statusMessage ?? "요청 중…").font(.caption)
                }
            } else if let status = viewModel.statusMessage {
                banner(status, systemImage: "checkmark.circle", tint: .green)
            }

            if let error = viewModel.errorMessage {
                banner(error, systemImage: "exclamationmark.triangle", tint: .red)
            }
        }
    }

    private func tappedAddressSection(_ address: ReverseGeocodedAddress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("탭한 지점 (Reverse Geocoding)")
            Text(address.displayAddress).font(.callout)
            Text(address.coordinate.apiQueryValue)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            if address.isInGyeongbuk {
                Text("경상북도 안에 있는 지점입니다.")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var geocodeResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("검색 결과 \(viewModel.geocodeResults.count)건")
            ForEach(viewModel.geocodeResults) { place in
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayAddress).font(.callout)
                    if !place.englishAddress.isEmpty {
                        Text(place.englishAddress).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button("출발지로") { viewModel.select(place, as: .start) }
                        Button("도착지로") { viewModel.select(place, as: .goal) }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
            }
        }
    }

    private var locationResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("도착지 검색 결과 \(viewModel.locationResults.count)건")
            ForEach(viewModel.locationResults) { location in
                Button { viewModel.select(location) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.title).font(.callout.bold())
                        if !location.category.isEmpty {
                            Text(location.category).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(location.displayAddress).font(.caption)
                        Text(location.coordinate.apiQueryValue)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 경로 결과

    private func routeSummarySection(_ route: DrivingRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("3. 경로 요약")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                summaryCell("거리", route.distanceDescription)
                summaryCell("소요 시간", route.durationDescription)
                summaryCell("통행료", "\(route.tollFare.formatted())원")
                summaryCell("유류비", "\(route.fuelPrice.formatted())원")
                summaryCell("택시 요금", "\(route.taxiFare.formatted())원")
                summaryCell("경로 점 수", "\(route.path.count)")
            }

            if !route.tollGateSteps.isEmpty {
                Text("톨게이트 안내 \(route.tollGateSteps.count)곳 감지 — TollGateService 입력으로 쓰입니다.")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    private func summaryCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10))
    }

    private func stepsSection(_ route: DrivingRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("4. 턴바이턴 안내 \(route.steps.count)개")
            Text("행을 누르면 지도에서 해당 지점으로 이동합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(spacing: 0) {
                ForEach(route.steps) { step in
                    Button {
                        viewModel.focus(on: step)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: step.kind.symbolName)
                                .frame(width: 22)
                                .foregroundStyle(step.kind == .tollGate ? Color.orange : Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.instructions.isEmpty ? "(안내 문구 없음)" : step.instructions)
                                    .font(.callout)
                                    .multilineTextAlignment(.leading)
                                Text("\(step.distance)m · 누적 \(step.distanceFromStart)m · type \(step.rawType) · \(step.kind.rawValue)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }

    private func sectionsSection(_ route: DrivingRoute) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("5. 도로 구간 \(route.sections.count)개")
            Text("SpeedLimitService 가 제한속도를 매칭할 대상입니다. speed 는 현재 통행 속도입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVStack(spacing: 0) {
                ForEach(route.sections) { section in
                    HStack {
                        Text(section.name.isEmpty ? "(이름 없음)" : section.name)
                            .font(.callout)
                        Spacer()
                        Text("\(section.distance)m · \(section.currentSpeed)km/h · \(section.congestionDescription)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }

    // MARK: - 공통

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
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

// MARK: - 지도 영역

/// 지도와 지도 자체의 상태(로딩/인증 실패)를 함께 보여 준다.
private struct MapPane: View {

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
    NaverMapsTestView()
}

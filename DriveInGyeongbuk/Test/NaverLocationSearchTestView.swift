//
//  NaverLocationSearchTestView.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] NAVER API HUB 지역 검색 API 단독 검증 화면.
//

import SwiftUI

struct NaverLocationSearchTestView: View {
    var onClose: (() -> Void)?

    @StateObject private var viewModel = NaverLocationSearchTestViewModel()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let warning = viewModel.credentialWarning {
                        banner(warning, systemImage: "key.slash", tint: .orange)
                    }

                    searchSection
                    statusSection

                    if let selected = viewModel.selectedLocation {
                        selectedSection(selected)
                    }

                    resultsSection
                }
                .padding(16)
            }
            .navigationTitle("도착지 검색 테스트")
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

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("업체·기관명 검색").font(.headline)
            Text("NAVER API HUB 지역 검색 API는 한 번에 최대 5건을 반환합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("예: 불국사, 경주역", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await viewModel.search() } }

                Button("검색") { Task { await viewModel.search() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if viewModel.isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text(viewModel.statusMessage ?? "검색 중…")
            }
            .font(.caption)
        } else if let status = viewModel.statusMessage {
            banner(status, systemImage: "checkmark.circle", tint: .green)
        }

        if let error = viewModel.errorMessage {
            banner(error, systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if !viewModel.results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("검색 결과").font(.headline)
                ForEach(viewModel.results) { location in
                    Button { viewModel.select(location) } label: {
                        resultCard(location)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultCard(_ location: NaverLocation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(location.title).font(.subheadline.bold())
                Spacer()
                if viewModel.selectedLocation?.id == location.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                }
            }
            if !location.category.isEmpty {
                Text(location.category).font(.caption).foregroundStyle(.secondary)
            }
            Text(location.displayAddress).font(.caption)
            Text(location.coordinate.apiQueryValue)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 12))
    }

    private func selectedSection(_ location: NaverLocation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("선택한 도착지", systemImage: "mappin.and.ellipse")
                .font(.headline)
                .foregroundStyle(.tint)
            Text(location.title).font(.subheadline.bold())
            Text(location.displayAddress).font(.caption)
            Text("위도 \(location.coordinate.latitude), 경도 \(location.coordinate.longitude)")
                .font(.caption2.monospacedDigit())
            Text("Directions 전달값: \(location.coordinate.apiQueryValue)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 12))
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

#Preview {
    NaverLocationSearchTestView()
}

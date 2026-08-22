//
//  SearchView.swift
//  DriveInGyeongbuk
//
//  Figma "Html → Body → The Device/App Canvas" 검색 화면.
//

import SwiftUI

struct SearchView: View {
    private static let background = Color(red: 11 / 255, green: 19 / 255, blue: 38 / 255)
    private static let panel = Color(red: 23 / 255, green: 31 / 255, blue: 51 / 255)
    private static let primaryText = Color(red: 218 / 255, green: 226 / 255, blue: 253 / 255)
    private static let secondaryText = Color(red: 195 / 255, green: 198 / 255, blue: 215 / 255)
    private static let iconTint = Color(red: 174 / 255, green: 193 / 255, blue: 255 / 255)

    @StateObject private var viewModel: SearchViewModel
    @FocusState private var isSearchFocused: Bool

    private let onSelect: (NaverLocation) -> Void
    private let automaticDemoQuery: String?

    init(initialQuery: String = "",
         automaticDemoQuery: String? = nil,
         onSelect: @escaping (NaverLocation) -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(initialQuery: initialQuery))
        self.automaticDemoQuery = automaticDemoQuery
        self.onSelect = onSelect
    }

    var body: some View {
        ZStack {
            Self.background.ignoresSafeArea()

            ScrollView {
                resultsPanel
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbarBackground(Self.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlassEffectContainer(spacing: 0) {
                    searchField
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 330)
                }
            }
        }
        .task {
            isSearchFocused = true
            if let automaticDemoQuery {
                await runAutomaticDemoSearch(query: automaticDemoQuery)
            } else if viewModel.canSearch {
                await viewModel.search()
            }
        }
    }

    /// 키보드가 올라온 뒤 글자가 실제 입력되는 모습을 보여 주고, 검색 결과가 나타나면
    /// 데모 목적지 행을 선택한다. 네트워크 검색 자체는 수동 검색과 완전히 같은 경로를 탄다.
    @MainActor
    private func runAutomaticDemoSearch(query: String) async {
        viewModel.clear()
        try? await Task.sleep(for: .milliseconds(550))
        guard !Task.isCancelled else { return }

        for character in query {
            viewModel.query.append(character)
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
        }

        try? await Task.sleep(for: .milliseconds(450))
        await viewModel.search()
        guard !Task.isCancelled else { return }

        let selected = viewModel.results.first {
            $0.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines) == query
        } ?? viewModel.results.first
        guard let selected else { return }

        // 결과가 나타난 것을 관객이 읽을 시간을 둔 뒤 행 선택을 재현한다.
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled else { return }
        isSearchFocused = false
        onSelect(selected)
    }

    private var searchField: some View {
        DestinationSearchField {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search destination", text: $viewModel.query)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(.primary)
                    .tint(Self.iconTint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onSubmit { Task { await viewModel.search() } }

                if viewModel.isLoading {
                    ProgressView()
                        .tint(Self.iconTint)
                        .frame(width: 32, height: 32)
                } else if !viewModel.query.isEmpty {
                    Button { viewModel.clear() } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear search")
                }
            }
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(viewModel.results.isEmpty ? "SUGGESTED" : "RESULTS")

            if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "exclamationmark.magnifyingglass")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await viewModel.search() } }
                }
                .foregroundStyle(Self.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 220)
                .padding(.horizontal)
            } else if viewModel.results.isEmpty {
                ContentUnavailableView("Search for a destination",
                                       systemImage: "location.magnifyingglass",
                                       description: Text("Enter a place name and press Search."))
                    .foregroundStyle(Self.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.results) { location in
                        resultRow(location)
                    }
                }
            }
        }
        .padding(.bottom, 17)
        .background(Self.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.37), radius: 32, y: 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Self.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .frame(height: 48)
    }

    private func resultRow(_ location: NaverLocation) -> some View {
        Button {
            onSelect(location)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Self.iconTint)
                    .frame(width: 40, height: 40)
                    .background(Self.panel, in: Circle())

                VStack(alignment: .leading, spacing: 0) {
                    Text(location.displayTitle)
                        .font(.body.weight(.bold))
                        .foregroundStyle(Self.primaryText)
                        .lineLimit(1)

                    Text(location.displayAddress.isEmpty ? location.displayCategory : location.displayAddress)
                        .font(.callout)
                        .foregroundStyle(Self.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Self.secondaryText)
            }
            .padding(.horizontal, 20)
            .frame(height: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SearchView { _ in }
    }
    .preferredColorScheme(.dark)
}

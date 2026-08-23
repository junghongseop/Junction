//
//  DebriefView.swift
//  DriveInGyeongbuk
//
//  주행이 끝난 뒤 처음 보는 화면. (피그마 "Debrief 1 - Drive Complete")
//
//  구조는 시안 그대로다 — 라벨 · 헤드라인 · 경로 한 줄 · 번호 붙은 안내 목록.
//  색만 앱의 네이비 팔레트로 옮겼다 (`DebriefStyle` 주석 참고).
//
//  시안과 다르게 한 것
//    · 목록 개수를 3개로 못박지 않는다. 고를 게 2개뿐이면 2개만 나온다.
//      감지된 사건이 없는 주행도 있고, 그때 빈 줄을 만들어 채우면 거짓말이 된다.
//    · 하단의 "Something's wrong with the car" 버튼은 이번 범위가 아니라 넣지 않았다.
//      (자리는 비워 두었으니 화면을 하나 더 붙이면 된다)
//

import SwiftUI

struct DebriefView: View {

    @StateObject private var viewModel: DebriefViewModel
    @State private var navigationPath: [DebriefLesson] = []
    @State private var hasAutomaticallyOpenedLesson = false
    @State private var demoSelectedLessonID: String?

    /// 닫기. 모달로 띄운 쪽이 넘겨 준다. 이미 있는 스택에 밀어 넣었으면 `nil` 이고,
    /// 그때는 Done 버튼 대신 기본 뒤로가기를 쓴다.
    private let onClose: (() -> Void)?

    /// 자기 `NavigationStack` 을 직접 만들지.
    ///
    /// 모달로 띄울 때는 `true`. 이미 스택 안이면 `false` 여야 한다 — 스택을 겹쳐 놓으면
    /// 안쪽 화면의 `navigationDestination` 이 바깥 스택과 따로 놀아서 링크가 죽는다.
    private let embedsNavigationStack: Bool

    init(recording: DriveRecording,
         service: DebriefServicing = DebriefService(),
         onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: DebriefViewModel(recording: recording, service: service))
        self.onClose = onClose
        self.embedsNavigationStack = true
    }

    /// 이미 만들어진 결과를 그대로 보여 준다. (미리보기 · 개발자 메뉴)
    ///
    /// - Parameter onClose: `nil` 이면 이미 있는 네비게이션 스택 안에 밀어 넣은 것으로 본다.
    init(debrief: Debrief, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: DebriefViewModel(debrief: debrief))
        self.onClose = onClose
        self.embedsNavigationStack = onClose != nil
    }

    var body: some View {
        Group {
            if embedsNavigationStack {
                NavigationStack(path: $navigationPath) { stackContent }
            } else {
                stackContent
            }
        }
        .task { await viewModel.load() }
        .task(id: viewModel.lessons.first?.id) {
            guard DemoDriveLocation.isAutomationEnabled,
                  embedsNavigationStack,
                  let firstLesson = viewModel.lessons.first,
                  !hasAutomaticallyOpenedLesson else { return }
            hasAutomaticallyOpenedLesson = true
            // Gemini가 만든 카드 제목과 목록을 먼저 보여 준 뒤 첫 카드를 선택한다.
            try? await Task.sleep(for: .seconds(1))
            demoSelectedLessonID = firstLesson.id
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            demoSelectedLessonID = nil
            navigationPath.append(firstLesson)
        }
        .preferredColorScheme(.dark)
    }

    private var stackContent: some View {
        // `content` 는 로딩/실패/요약을 오가는 조건 분기다. 그 결과에 직접
        // `navigationDestination` 을 붙이면 안 된다 — 분기가 바뀔 때 목적지 등록이
        // 날아가서 `NavigationLink` 가 눌려도 아무 일도 안 일어난다.
        // 그래서 항상 존재하는 컨테이너에 붙인다.
        ZStack {
            DebriefStyle.background.ignoresSafeArea()
            content
        }
        .navigationDestination(for: DebriefLesson.self) { lesson in
            DebriefLessonView(lesson: lesson)
        }
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onClose)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DebriefStyle.accent)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: -

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loading
        } else if let errorMessage = viewModel.errorMessage {
            failure(errorMessage)
        } else {
            summary
        }
    }

    private var loading: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Looking back over your drive…")
                .font(.system(size: 15))
                .foregroundStyle(DebriefStyle.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Debrief unavailable", systemImage: "text.magnifyingglass")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") { Task { await viewModel.retry() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                if viewModel.hasNothingToReport {
                    nothingToReport
                } else {
                    lessonList
                }
            }
            .padding(.horizontal, DebriefStyle.horizontalMargin)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            DebriefStyle.eyebrow("Drive complete")

            Text(viewModel.headline)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(DebriefStyle.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let routeDescription = viewModel.routeDescription {
                Text(routeDescription)
                    .font(.system(size: 15))
                    .foregroundStyle(DebriefStyle.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lessonList: some View {
        VStack(alignment: .leading, spacing: 16) {
            DebriefStyle.eyebrow(viewModel.lessonCountLabel, color: DebriefStyle.secondaryText)

            VStack(spacing: 10) {
                ForEach(Array(viewModel.lessons.enumerated()), id: \.element.id) { index, lesson in
                    NavigationLink(value: lesson) {
                        lessonRow(number: index + 1, title: lesson.title)
                    }
                    .buttonStyle(.plain)
                    .demoInteraction("Open Gemini briefing",
                                     isActive: demoSelectedLessonID == lesson.id,
                                     labelPosition: .below)
                }
            }
        }
    }

    private func lessonRow(number: Int, title: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DebriefStyle.positive)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DebriefStyle.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DebriefStyle.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(DebriefStyle.row, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DebriefStyle.hairline))
        .contentShape(.rect)
    }

    /// 사건이 없었거나, 있어도 지금 설명할 만한 게 아니었을 때.
    /// 억지로 카드를 만들지 않고 그렇다고 말한다.
    private var nothingToReport: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.nothingToReportTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DebriefStyle.primaryText)
            Text(viewModel.nothingToReportMessage)
                .font(.system(size: 15))
                .foregroundStyle(DebriefStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .debriefCardStyle()
    }
}

#Preview("안내 2건") {
    DebriefView(debrief: DebriefSampleData.firstDriveToGyeongju) {}
}

#Preview("안내 없음") {
    DebriefView(debrief: DebriefSampleData.uneventfulDrive) {}
}

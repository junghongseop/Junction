//
//  DebriefSimulationView.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] 차를 몰지 않고 Debrief 전 과정을 돌려 본다.
//
//  하는 일
//    ① 실제 Directions 5 로 경로를 탐색한다              (진짜 경로)
//    ② 실제 제한속도 DB 로 구간을 만든다                  (진짜 공공데이터)
//    ③ 그 위를 달린 척하는 위치 기록을 만든다             ← 여기만 가짜다
//    ④ 감지 → 주제 선정 → 설명 → 화면                    (제품과 완전히 같은 코드)
//
//  즉 지어내는 건 "언제 어디를 몇 km/h 로 지났는가" 하나뿐이고, 그 뒤는 실제 주행과
//  같은 길을 탄다. 감지 규칙을 고치고 결과를 바로 확인할 수 있어야 해서 이렇게 짰다.
//
//  ⚠️ 제품 코드가 아니다. Settings > Developer 에서만 들어온다. 출시 전에 걷어낸다.
//

import SwiftUI

struct DebriefSimulationView: View {

    let onClose: () -> Void

    @StateObject private var viewModel = DebriefSimulationViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("운전 습관", selection: $viewModel.behaviour) {
                        ForEach(DebriefSimulationViewModel.Behaviour.allCases) { behaviour in
                            Text(behaviour.title).tag(behaviour)
                        }
                    }
                    Stepper("도착 후 정차 \(viewModel.parkingMinutes)분",
                            value: $viewModel.parkingMinutes, in: 0...20)
                } header: {
                    Text("가짜 주행 설정")
                } footer: {
                    Text(viewModel.behaviour.explanation)
                }

                Section("경로") {
                    LabeledContent("출발", value: DebriefSimulationViewModel.originName)
                    LabeledContent("도착", value: DebriefSimulationViewModel.destinationName)
                }

                Section {
                    LabeledContent("안내문 생성", value: viewModel.llmDescription)
                } footer: {
                    Text(viewModel.llmFooter)
                }

                Section {
                    Button {
                        Task { await viewModel.run() }
                    } label: {
                        HStack {
                            Text("가짜 주행 후 Debrief 열기")
                            Spacer()
                            if viewModel.isRunning { ProgressView() }
                        }
                    }
                    .disabled(viewModel.isRunning)

                    Button("샘플 데이터로 화면만 보기") {
                        viewModel.showSampleDebrief()
                    }
                }

                if let status = viewModel.statusMessage {
                    Section("진행") {
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let debrief = viewModel.debrief {
                    detectedSection(debrief)
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("오류") {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Debrief 시뮬레이션")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기", action: onClose)
                }
            }
        }
        .fullScreenCover(item: $viewModel.presentedDebrief) { debrief in
            DebriefView(debrief: debrief) { viewModel.presentedDebrief = nil }
        }
    }

    /// 감지된 사건 전부를 그대로 보여 준다. 화면에는 고른 것만 나오므로,
    /// 규칙이 의도대로 도는지는 여기서 확인해야 한다.
    private func detectedSection(_ debrief: Debrief) -> some View {
        Group {
            Section("감지된 사건 \(debrief.events.count)건") {
                if debrief.events.isEmpty {
                    Text("없음").foregroundStyle(.secondary)
                }
                ForEach(debrief.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(event.id) · \(event.kind.rawValue)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(event.summary).font(.footnote)
                        ForEach(event.facts, id: \.key) { fact in
                            Text("· \(fact.key): \(fact.value)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("고른 안내 \(debrief.lessons.count)건") {
                ForEach(debrief.lessons) { lesson in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lesson.title).font(.footnote.weight(.semibold))
                        Text("topic: \(lesson.lesson.topicID.rawValue) · event: \(lesson.lesson.eventID ?? "-")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let reason = lesson.lesson.reason {
                            Text(reason).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !debrief.dataWarnings.isEmpty {
                Section("데이터 경고") {
                    ForEach(debrief.dataWarnings, id: \.self) { warning in
                        Text(warning).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

#Preview {
    DebriefSimulationView(onClose: {})
}

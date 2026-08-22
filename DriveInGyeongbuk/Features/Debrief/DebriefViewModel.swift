//
//  DebriefViewModel.swift
//  DriveInGyeongbuk
//
//  Debrief 화면의 상태.
//
//  화면이 받는 건 `DriveRecording` 하나뿐이고, 나머지는 `DebriefServicing` 이 만든다.
//  이미 만들어진 `Debrief` 를 그대로 넣는 길(`init(debrief:)`)도 열어 뒀다 —
//  미리보기와 개발자 메뉴가 서비스를 안 태우고 화면만 보기 위해서다.
//

import Combine
import Foundation

final class DebriefViewModel: ObservableObject {

    // MARK: 출력

    @Published private(set) var debrief: Debrief?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: 의존성

    private let recording: DriveRecording?
    private let service: DebriefServicing

    /// 주행 기록에서 새로 만든다.
    init(recording: DriveRecording,
         service: DebriefServicing = DebriefService()) {
        self.recording = recording
        self.service = service
    }

    /// 이미 만들어진 결과를 그대로 보여 준다. (미리보기 · 개발자 메뉴)
    init(debrief: Debrief) {
        self.recording = nil
        self.service = DebriefService()
        self.debrief = debrief
    }

    // MARK: 화면 이벤트

    func load() async {
        guard debrief == nil, !isLoading, let recording else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            debrief = try await service.makeDebrief(for: recording)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func retry() async {
        errorMessage = nil
        await load()
    }

    // MARK: 파생 값

    /// Figma 1번 화면 헤드라인.
    ///
    /// LLM 이 쓴 `summary` 를 우선 쓰고, 없을 때만 코드가 만든 문장으로 물러선다.
    var headline: String {
        if let summary = debrief?.report.summary, !summary.isEmpty { return summary }
        guard let recording = debrief?.recording ?? recording else { return "Drive complete." }
        return recording.isFirstDriveInKorea
            ? "Your first drive in Gyeongbuk is complete."
            : "Drive complete."
    }

    /// "Pohang → Gyeongju · 32 km" 자리.
    var routeDescription: String? {
        let description = (debrief?.recording ?? recording)?.routeDescription
        return description?.isEmpty == false ? description : nil
    }

    var lessons: [DebriefLesson] { debrief?.lessons ?? [] }

    /// "3 THINGS TO KNOW" 자리의 라벨.
    var lessonCountLabel: String {
        let count = lessons.count
        return count == 1 ? "1 thing to know" : "\(count) things to know"
    }

    /// 감지는 됐는데 고를 만한 게 없었던 경우와, 애초에 아무 일도 없었던 경우를 구분한다.
    var hasNothingToReport: Bool {
        debrief != nil && lessons.isEmpty
    }
}

//
//  DebriefSimulationViewModel.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] `DebriefSimulationView` 의 상태.
//
//  경로 탐색 → 제한속도 구간 → 가짜 주행 → Debrief 순으로 실제 서비스를 그대로 태운다.
//  각 단계의 실패는 삼키지 않고 `statusMessage` / `errorMessage` 에 남긴다 —
//  어디서 막혔는지 보여야 시뮬레이터로서 쓸모가 있다.
//

import Combine
import Foundation

final class DebriefSimulationViewModel: ObservableObject {

    /// 포항시청. 데모 경로의 출발점.
    static let origin = NaverCoordinate(latitude: 36.0190, longitude: 129.3435)
    /// 경주 첨성대. 제한속도 단계가 여러 번 바뀌고 톨게이트도 지난다.
    static let destination = NaverCoordinate(latitude: 35.8347, longitude: 129.2194)
    static let originName = "Pohang City Hall"
    static let destinationName = "Cheomseongdae, Gyeongju"

    enum Behaviour: String, CaseIterable, Identifiable {
        case lateToSlowDown
        case attentive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lateToSlowDown: return "감속이 늦음"
            case .attentive: return "표지판을 잘 따름"
            }
        }

        var explanation: String {
            switch self {
            case .lateToSlowDown:
                return "제한속도가 떨어져도 260m 정도는 이전 속도로 달린다. 과속 사건이 감지된다."
            case .attentive:
                return "항상 제한속도 아래로 달린다. 과속 사건이 감지되지 않는다."
            }
        }

        var simulatorBehaviour: DriveSimulator.Behaviour {
            switch self {
            case .lateToSlowDown: return .lateToSlowDown(metersLate: 260, overshootKPH: 14)
            case .attentive: return .attentive
            }
        }
    }

    // MARK: 입력

    @Published var behaviour: Behaviour = .lateToSlowDown
    @Published var parkingMinutes = 6

    // MARK: 출력

    @Published var presentedDebrief: Debrief?
    @Published private(set) var debrief: Debrief?
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    // MARK: 의존성

    private let directionsService: NaverDirectionsServicing
    private let debriefService: DebriefServicing

    init(directionsService: NaverDirectionsServicing = NaverDirectionsService(),
         debriefService: DebriefServicing = DebriefService()) {
        self.directionsService = directionsService
        self.debriefService = debriefService
    }

    /// 지금 어떤 LLM 클라이언트를 태우는지. 키를 넣었는데 목이 돌면 바로 알아채야 한다.
    var llmDescription: String {
        DebriefLLMClientFactory.usesLiveLLM ? "Gemini (\(GeminiConfiguration.default.model))" : "규칙 기반 목"
    }

    var llmFooter: String {
        DebriefLLMClientFactory.usesLiveLLM
            ? "Gemini 호출이 실패하면 규칙 기반 문구로 자동 대체되고, 사유가 아래 '데이터 경고' 에 남습니다."
            : "Config.xcconfig 의 Gemini_API_Key 가 비어 있어 규칙 기반으로 돕니다. 감지 · 화면은 동일하게 동작합니다."
    }

    // MARK: -

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        debrief = nil
        defer { isRunning = false }

        do {
            statusMessage = "① 경로를 탐색하는 중…"
            let routes = try await directionsService.routes(from: Self.origin,
                                                            to: Self.destination,
                                                            waypoints: [],
                                                            options: [.fastest])
            guard let route = routes.first else {
                errorMessage = "경로를 찾지 못했습니다."
                statusMessage = nil
                return
            }

            statusMessage = "② 제한속도 구간을 만드는 중… (경로 \(route.distanceDescription))"
            let segments = await speedLimitSegments(for: route)

            statusMessage = "③ 가짜 주행을 만드는 중… (제한속도 구간 \(segments.count)개)"
            var simulator = DriveSimulator()
            simulator.parkingMinutesAtGoal = parkingMinutes
            let recording = simulator.simulate(route: route,
                                               segments: segments,
                                               behaviour: behaviour.simulatorBehaviour,
                                               originName: Self.originName,
                                               destinationName: Self.destinationName,
                                               isFirstDriveInKorea: true)

            statusMessage = "④ Debrief 를 만드는 중… (위치 기록 \(recording.samples.count)건)"
            let result = try await debriefService.makeDebrief(for: recording)

            debrief = result
            presentedDebrief = result
            statusMessage = "완료 — 사건 \(result.events.count)건, 안내 \(result.lessons.count)건."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = nil
        }
    }

    /// 손으로 만든 결과로 화면만 확인한다. 네트워크·DB 를 타지 않는다.
    func showSampleDebrief() {
        let sample = DebriefSampleData.firstDriveToGyeongju
        debrief = sample
        presentedDebrief = sample
        statusMessage = "샘플 데이터를 띄웠습니다. (감지 규칙은 확인되지 않습니다)"
    }

    // MARK: -

    /// 시뮬레이터가 낼 속도를 정하려면 제한속도 구간이 필요하다.
    /// `DebriefService` 도 같은 조회를 하지만, 그건 그 안에서 다시 한다 — 여기서 넘겨줄 통로가 없다.
    /// 데모용이라 두 번 읽는 비용은 감수한다.
    private func speedLimitSegments(for route: DrivingRoute) async -> [RouteSpeedLimitSegment] {
        guard let service = try? SpeedLimitService() else { return [] }
        do {
            try await service.prepare(for: route)
            return service.routeSegments
        } catch {
            return []
        }
    }
}

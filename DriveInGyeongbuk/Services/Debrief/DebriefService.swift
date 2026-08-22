//
//  DebriefService.swift
//  DriveInGyeongbuk
//
//  주행 기록 하나를 받아 화면에 띄울 Debrief 를 만들어 낸다. 파이프라인의 조립부다.
//
//      DriveRecording
//        ↓  ① 공공데이터 조회 (제한속도 구간 · 주정차 금지구간)
//      DriveEventContext
//        ↓  ② 규칙 기반 감지        — AI 없음, 결정적
//      [DriveEvent]
//        ↓  ③ 관련 주제의 검증 콘텐츠를 붙인다
//      DebriefRequest
//        ↓  ④ LLM — 무엇을 설명할지 고르고 다시 서술한다
//      DebriefReport
//        ↓  ⑤ 사건·주제를 되붙여 화면이 쓸 형태로
//      Debrief
//
//  ①은 네트워크와 SQLite 를 타서 실패할 수 있다. **실패해도 파이프라인은 멈추지 않는다.**
//  못 불러온 데이터에 기대는 감지기가 조용히 아무것도 안 내놓을 뿐이다. 주행이 끝난 뒤에
//  "안내를 만들지 못했습니다"만 띄우는 것보다, 알 수 있는 만큼이라도 말해 주는 게 낫다.
//

import Foundation

/// 화면이 받는 최종 결과.
nonisolated struct Debrief: Identifiable, Hashable {

    var id: UUID
    var recording: DriveRecording
    /// 감지된 사건 전부. 화면에는 고른 것만 나오지만 개발자 화면에서 전부 본다.
    var events: [DriveEvent]
    /// LLM 이 고르고 쓴 것.
    var report: DebriefReport
    /// 안내 카드. `report.lessons` 에 사건·주제를 되붙인 것이다.
    var lessons: [DebriefLesson]

    /// 데이터를 일부 못 불러온 경우의 사유. 정상이면 비어 있다.
    /// 화면에 크게 띄우진 않지만 개발자 화면에서 원인을 볼 수 있어야 한다.
    var dataWarnings: [String] = []
}

/// 카드 한 장에 필요한 것 전부.
nonisolated struct DebriefLesson: Identifiable, Hashable {
    var lesson: DebriefReport.Lesson
    /// 근거가 된 사건. 없을 수 있다.
    var event: DriveEvent?
    /// 검증된 콘텐츠. 도해와 출처가 여기서 나온다.
    var topic: DebriefTopic

    var id: String { lesson.id }
    var title: String { lesson.title }
    var explanation: String { lesson.explanation }
}

// MARK: -

protocol DebriefServicing {
    func makeDebrief(for recording: DriveRecording) async throws -> Debrief
}

final class DebriefService: DebriefServicing {

    /// 주정차 금지구간을 목적지 반경 몇 m 까지 볼지. 서버 고정 반경(2km)을 넘길 수 없다.
    var enforcementRadiusMeters: Int = 1000

    private let detector: DriveEventDetectorProtocol
    private let repository: TrafficRuleRepositoryProtocol
    private let llmClient: DebriefLLMClient
    /// LLM 호출이 실패했을 때 쓰는 대체. 네트워크도 키도 필요 없다.
    private let fallbackLLMClient: DebriefLLMClient?
    private let profile: DriverProfileStoring
    /// 제한속도 조회. DB 를 못 열 수도 있어서 옵셔널이다.
    private let speedLimitServiceFactory: () -> SpeedLimitServicing?
    private let enforcementService: EnforcementServicing

    init(detector: DriveEventDetectorProtocol = DriveEventDetector(),
         repository: TrafficRuleRepositoryProtocol = TrafficRuleRepository(),
         llmClient: DebriefLLMClient = DebriefLLMClientFactory.makeDefault(),
         fallbackLLMClient: DebriefLLMClient? = DebriefLLMClientFactory.makeFallback(),
         profile: DriverProfileStoring = DriverProfileStore(),
         enforcementService: EnforcementServicing = EnforcementService(),
         speedLimitServiceFactory: @escaping () -> SpeedLimitServicing? = { try? SpeedLimitService() }) {
        self.detector = detector
        self.repository = repository
        self.llmClient = llmClient
        self.fallbackLLMClient = fallbackLLMClient
        self.profile = profile
        self.enforcementService = enforcementService
        self.speedLimitServiceFactory = speedLimitServiceFactory
    }

    // MARK: -

    func makeDebrief(for recording: DriveRecording) async throws -> Debrief {

        var warnings: [String] = []

        // ① 공공데이터. 둘 다 실패해도 계속 간다.
        //
        // 한쪽은 네트워크(콜드 스타트 수십 초), 다른 쪽은 SQLite 다. 줄 세울 이유가 없어
        // 같이 띄운다 — 주행이 끝난 화면에서 기다리는 시간이 그만큼 줄어든다.
        async let loadedSegments = loadSpeedLimitSegments(for: recording)
        async let loadedZones = loadEnforcementZones(for: recording)

        let (segments, segmentWarnings) = await loadedSegments
        let (zones, zoneWarnings) = await loadedZones
        warnings.append(contentsOf: segmentWarnings)
        warnings.append(contentsOf: zoneWarnings)

        let context = DriveEventContext(
            recording: recording,
            speedLimitSegments: segments,
            enforcementZones: zones,
            enforcementCenter: recording.route?.goal,
            enforcementRadiusMeters: Double(enforcementRadiusMeters)
        )

        // ② 규칙 기반 감지.
        let events = detector.events(in: context)

        // ③ 사건이 가리키는 주제의 검증 콘텐츠만 추린다.
        //    쓰지도 않을 주제를 다 넣으면 프롬프트만 길어지고 고르는 쪽이 흐려진다.
        let topicIDs = events.flatMap(\.relatedTopicIDs)
        let topics = repository.topics(for: topicIDs)

        // ④ LLM.
        let request = DebriefRequest(
            driver: .init(language: profile.preferredLanguage,
                          isFirstDriveInKorea: recording.isFirstDriveInKorea),
            trip: .init(origin: recording.originName,
                        destination: recording.destinationName,
                        distanceDescription: recording.distanceDescription,
                        durationDescription: recording.durationDescription),
            events: events,
            availableTopics: topics
        )

        let report = try await makeReport(for: request, warnings: &warnings)

        // ⑤ 되붙이기. 우리가 준 적 없는 주제를 골라 왔으면 그 카드는 버린다.
        //    환각을 화면에 올리느니 카드 한 장이 없는 편이 낫다.
        let lessons: [DebriefLesson] = report.lessons.compactMap { lesson in
            guard let topic = repository.topic(lesson.topicID) else {
                warnings.append("준비되지 않은 주제를 골라 카드를 버렸습니다: \(lesson.topicID.rawValue)")
                return nil
            }
            return DebriefLesson(lesson: lesson,
                                 event: events.first { $0.id == lesson.eventID },
                                 topic: topic)
        }

        return Debrief(id: recording.id,
                       recording: recording,
                       events: events,
                       report: report,
                       lessons: lessons,
                       dataWarnings: warnings)
    }

    // MARK: - LLM

    /// LLM 을 부르되, 실패하면 대체 클라이언트로 한 번 더 시도한다.
    ///
    /// 실패를 삼키는 게 아니라 **사유를 `warnings` 에 남기고** 계속 간다.
    /// 주행이 다 끝난 뒤에 "쿼터 초과" 하나 때문에 아무 말도 못 하는 화면을 띄우는 것보다,
    /// 규칙 기반 문구로라도 안내를 보여 주는 편이 낫다. 대체 클라이언트마저 없으면 그때는 던진다.
    private func makeReport(for request: DebriefRequest,
                            warnings: inout [String]) async throws -> DebriefReport {
        do {
            return try await llmClient.makeReport(for: request)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            guard let fallbackLLMClient else { throw error }

            warnings.append("LLM 안내 생성에 실패해 규칙 기반 문구로 대체했습니다: \(reason)")
            return try await fallbackLLMClient.makeReport(for: request)
        }
    }

    // MARK: - 공공데이터

    /// 실패 사유는 던지지 않고 `warnings` 로 함께 돌려준다. 이 단계는 멈출 이유가 아니다.
    private func loadSpeedLimitSegments(
        for recording: DriveRecording
    ) async -> (segments: [RouteSpeedLimitSegment], warnings: [String]) {

        guard let route = recording.route else { return ([], []) }
        guard let service = speedLimitServiceFactory() else {
            return ([], ["제한속도 데이터베이스를 열지 못해 속도 관련 안내를 건너뛰었습니다."])
        }
        // 경상북도 전용 데이터셋이다. 도 밖이면 조회 자체가 헛수고다.
        guard KoreaCoordinateConverter.isInsideDataset(route.goal) else {
            return ([], ["경상북도 밖이라 제한속도 데이터를 쓸 수 없습니다."])
        }

        do {
            try await service.prepare(for: route)
            return (service.routeSegments, [])
        } catch {
            return ([], ["제한속도 구간을 불러오지 못했습니다: \(error.localizedDescription)"])
        }
    }

    private func loadEnforcementZones(
        for recording: DriveRecording
    ) async -> (zones: [EnforcementZone], warnings: [String]) {

        guard let goal = recording.route?.goal else { return ([], []) }

        do {
            let zones = try await enforcementService.zones(near: goal,
                                                           radiusMeters: enforcementRadiusMeters)
            return (zones, [])
        } catch {
            return ([], ["주정차 금지구간을 불러오지 못했습니다: \(error.localizedDescription)"])
        }
    }
}

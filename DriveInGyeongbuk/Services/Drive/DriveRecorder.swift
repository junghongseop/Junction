//
//  DriveRecorder.swift
//  DriveInGyeongbuk
//
//  주행 중 위치 갱신을 모아 `DriveRecording` 을 만든다.
//
//  위치 구독을 직접 하지 않는 이유
//    `LocationServicing.onChange` 는 클로저가 하나뿐이라, 레코더가 직접 구독하면
//    이미 그것을 쓰고 있는 `MapHomeViewModel` 의 구독이 끊긴다. 그래서 레코더는
//    수동 수집기로 두고, 위치 갱신을 이미 받고 있는 쪽이 `record(_:)` 로 넘겨 준다.
//    덕분에 레코더는 의존성이 없고 테스트도 배열만 밀어 넣으면 된다.
//
//  쓰는 법
//    recorder.start(route: route, destinationName: "경주")
//    recorder.record(locationService.lastFix)   // 위치 갱신마다
//    let recording = recorder.finish()          // 주행 종료
//

import Foundation

protocol DriveRecorderProtocol: AnyObject {

    /// 기록 중인지.
    var isRecording: Bool { get }

    /// 기록을 시작한다. 이미 기록 중이면 이전 기록을 버리고 새로 시작한다.
    func start(route: DrivingRoute?, originName: String?, destinationName: String?)

    /// 위치 갱신 한 건을 넘긴다. 기록 중이 아니거나 `nil` 이면 무시한다.
    func record(_ fix: LocationFix?)

    /// 기록을 끝내고 결과를 돌려준다. 기록 중이 아니었으면 `nil`.
    @discardableResult
    func finish() -> DriveRecording?

    /// 결과를 버리고 멈춘다.
    func cancel()
}

extension DriveRecorderProtocol {
    func start(route: DrivingRoute?, destinationName: String?) {
        start(route: route, originName: nil, destinationName: destinationName)
    }
}

// MARK: -

final class DriveRecorder: DriveRecorderProtocol {

    /// 같은 자리에서 온 갱신을 걸러 낼 최소 이동 거리(m).
    /// 신호 대기 중에도 GPS 는 계속 흔들려서 그대로 두면 샘플이 수천 개로 불어난다.
    /// 정차 판정은 시간 기준이라 이 값 때문에 놓치지 않는다 (정차 중에도 시간은 기록된다).
    var minimumSampleDistanceMeters: Double = 5
    /// 위와 별개로, 이 시간이 지나면 안 움직였어도 한 건 남긴다. 정차 구간의 길이를 알기 위해서다.
    var maximumSampleIntervalSeconds: TimeInterval = 10

    private(set) var isRecording = false

    private var route: DrivingRoute?
    private var originName: String?
    private var destinationName: String?
    private var startedAt: Date?
    private var samples: [DriveSample] = []
    /// 같은 위치 갱신이 두 번 들어오는 걸 막는다 (`onChange` 는 권한 변화로도 불린다).
    private var lastRecordedTimestamp: Date?

    private let profile: DriverProfileStoring

    init(profile: DriverProfileStoring = DriverProfileStore()) {
        self.profile = profile
    }

    // MARK: -

    func start(route: DrivingRoute?, originName: String?, destinationName: String?) {
        self.route = route
        self.originName = originName
        self.destinationName = destinationName
        self.startedAt = .now
        self.samples = []
        self.lastRecordedTimestamp = nil
        self.isRecording = true
    }

    func record(_ fix: LocationFix?) {
        guard isRecording, let fix else { return }
        // 같은 갱신이 두 번 들어오는 경우.
        guard fix.timestamp != lastRecordedTimestamp else { return }

        if let previous = samples.last {
            let moved = previous.coordinate.distance(to: fix.coordinate)
            let elapsed = fix.timestamp.timeIntervalSince(previous.timestamp)
            guard moved >= minimumSampleDistanceMeters || elapsed >= maximumSampleIntervalSeconds else { return }
        }

        lastRecordedTimestamp = fix.timestamp
        samples.append(DriveSample(fix: fix))
    }

    @discardableResult
    func finish() -> DriveRecording? {
        guard isRecording, let startedAt else { return nil }

        let recording = DriveRecording(
            route: route,
            originName: originName,
            destinationName: destinationName,
            startedAt: startedAt,
            // 마지막 샘플 시각이 있으면 그쪽이 정확하다. 종료 버튼을 늦게 눌렀을 수도 있다.
            endedAt: samples.last?.timestamp ?? .now,
            samples: samples,
            isFirstDriveInKorea: profile.completedDriveCount == 0
        )

        profile.recordCompletedDrive()
        reset()
        return recording
    }

    func cancel() {
        reset()
    }

    private func reset() {
        isRecording = false
        route = nil
        originName = nil
        destinationName = nil
        startedAt = nil
        samples = []
        lastRecordedTimestamp = nil
    }
}

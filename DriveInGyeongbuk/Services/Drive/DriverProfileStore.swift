//
//  DriverProfileStore.swift
//  DriveInGyeongbuk
//
//  운전자에 대해 앱이 아는 몇 안 되는 사실.
//
//  Debrief 는 "한국에서 처음 운전하는 사람인가"에 따라 무엇을 먼저 설명할지가 달라진다.
//  지금 앱에는 계정도 온보딩도 없어서, 완료한 주행 횟수를 세는 것으로 대신한다.
//  온보딩이 생기면 이 구현만 바꾸면 된다.
//
//  ⚠️ 이 값은 LLM 의 "우선순위 선정"에만 쓰이는 힌트다. 법규 판단에는 관여하지 않는다.
//

import Foundation

protocol DriverProfileStoring: AnyObject {
    /// 지금까지 끝낸 주행 횟수.
    var completedDriveCount: Int { get }
    /// 안내 문구를 만들 언어. 지금은 영어 고정.
    var preferredLanguage: String { get }

    func recordCompletedDrive()
}

final class DriverProfileStore: DriverProfileStoring {

    private enum Key {
        static let completedDriveCount = "drive.completedDriveCount"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completedDriveCount: Int {
        defaults.integer(forKey: Key.completedDriveCount)
    }

    // TODO: 온보딩에서 언어를 고르게 되면 여기서 읽어 온다.
    var preferredLanguage: String { "English" }

    func recordCompletedDrive() {
        defaults.set(completedDriveCount + 1, forKey: Key.completedDriveCount)
    }
}

/// 미리보기·개발자 메뉴용. 저장하지 않는다.
final class InMemoryDriverProfileStore: DriverProfileStoring {

    private(set) var completedDriveCount: Int
    var preferredLanguage: String { "English" }

    init(completedDriveCount: Int = 0) {
        self.completedDriveCount = completedDriveCount
    }

    func recordCompletedDrive() {
        completedDriveCount += 1
    }
}

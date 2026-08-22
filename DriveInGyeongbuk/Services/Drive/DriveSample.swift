//
//  DriveSample.swift
//  DriveInGyeongbuk
//
//  주행 중 한 번의 위치 갱신을 그대로 담아 둔 것.
//
//  `LocationService` 는 지금까지 좌표만 노출했다. Debrief 는 "언제 · 얼마나 빨리"까지
//  있어야 사건을 판정할 수 있어서, 위치 갱신 원본을 잃지 않고 모아 두는 그릇을 따로 뒀다.
//
//  ⚠️ 이 타입은 **LLM 에 절대 넘어가지 않는다.** GPS 원본 해석은 코드(`DriveEventDetector`)의
//  몫이고, LLM 은 그 결과인 `DriveEvent` 만 본다. `DebriefRequest` 가 이 타입을
//  참조하지 않는 것이 그 경계다.
//

import CoreLocation
import Foundation

nonisolated struct DriveSample: Hashable {

    var coordinate: NaverCoordinate
    /// 위치가 측정된 시각. 기록 시각이 아니라 `CLLocation.timestamp` 다.
    var timestamp: Date
    /// 대지 속도(km/h). GPS 가 속도를 못 준 갱신이면 `nil`.
    var speedKPH: Int?
    /// 진행 방위(도, 북쪽 0). 정지 상태에서는 `nil` 인 경우가 많다.
    var courseDegrees: Double?

    init(coordinate: NaverCoordinate,
         timestamp: Date,
         speedKPH: Int? = nil,
         courseDegrees: Double? = nil) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.speedKPH = speedKPH
        self.courseDegrees = courseDegrees
    }

    init(fix: LocationFix) {
        self.coordinate = fix.coordinate
        self.timestamp = fix.timestamp
        // CoreLocation 은 속도를 m/s 로 주고, 못 잰 경우 음수를 준다 (`LocationFix` 가 이미 걸러 둔다).
        self.speedKPH = fix.speedMPS.map { Int((($0 * 3.6)).rounded()) }
        self.courseDegrees = fix.courseDegrees
    }
}

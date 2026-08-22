//
//  RoadSignService.swift
//  DriveInGyeongbuk
//
//  ⚠️ 아직 껍데기(stub)입니다. 인터페이스만 정의되어 있고 구현은 비어 있습니다.
//
//  한국어 도로 표지판 인식.
//  두 가지 입력을 상정한다.
//    1) 경로 안내 문구(`RouteStep.instructions`) — 네트워크만으로 동작
//    2) 카메라 프레임 — Vision + OCR 로 실제 표지판을 읽는 경우
//

import Foundation

/// 인식된 도로 표지판.
struct RoadSign: Identifiable, Hashable {
    var id = UUID()

    var category: Category
    /// 표지판에 적힌 한국어 원문.
    var koreanText: String
    /// 인식 신뢰도 0...1.
    var confidence: Double
    /// 표지판이 있는(또는 안내가 걸린) 지점.
    var coordinate: NaverCoordinate?

    /// 한국 도로표지 규칙 기준 분류.
    enum Category: String, Hashable {
        /// 주의 표지
        case warning
        /// 규제 표지 (속도, 진입금지 등)
        case regulatory
        /// 지시 표지
        case mandatory
        /// 보조 표지
        case auxiliary
        /// 노면 표시
        case roadMarking
        /// 방향 안내 표지
        case direction
        case unknown
    }
}

protocol RoadSignServicing {
    /// 경로 안내 문구에서 표지판성 정보를 뽑아낸다.
    func signs(from step: RouteStep) -> [RoadSign]

    /// 카메라 프레임에서 표지판을 인식한다.
    /// - Parameter imageData: JPEG/PNG 등 인코딩된 이미지.
    func recognizeSigns(in imageData: Data) async throws -> [RoadSign]
}

// MARK: - Stub

/// TODO: Vision(VNRecognizeTextRequest) 기반 OCR + 규칙 매칭 구현.
struct RoadSignService: RoadSignServicing {

    init() {}

    func signs(from step: RouteStep) -> [RoadSign] {
        // TODO: instructions 를 파싱해 방향/규제 표지로 변환.
        []
    }

    func recognizeSigns(in imageData: Data) async throws -> [RoadSign] {
        // TODO: 이미지에서 표지판 영역 검출 → OCR → Category 분류.
        []
    }
}

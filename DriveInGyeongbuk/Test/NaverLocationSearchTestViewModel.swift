//
//  NaverLocationSearchTestViewModel.swift
//  DriveInGyeongbuk
//
//  [테스트 전용] NAVER API HUB 지역 검색 API 검증 화면의 상태.
//

import Combine
import Foundation

final class NaverLocationSearchTestViewModel: ObservableObject {
    @Published var query = "불국사"
    @Published private(set) var results: [NaverLocation] = []
    @Published private(set) var selectedLocation: NaverLocation?
    @Published private(set) var isLoading = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let service: NaverLocationSearchServicing

    init(service: NaverLocationSearchServicing = NaverLocationSearchService()) {
        self.service = service
    }

    var credentialWarning: String? {
        AppConfig.hasNaverSearchCredentials
            ? nil
            : "Config/Config.xcconfig에 Naver_Search_Client_ID와 Naver_Search_Client_Secret을 설정해 주세요."
    }

    func search() async {
        isLoading = true
        statusMessage = "지역 검색 API를 호출하는 중…"
        errorMessage = nil
        selectedLocation = nil
        defer { isLoading = false }

        do {
            results = try await service.search(query: query, display: 5)
            statusMessage = "‘\(query.trimmingCharacters(in: .whitespacesAndNewlines))’ 검색 결과 \(results.count)건"
        } catch {
            results = []
            statusMessage = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func select(_ location: NaverLocation) {
        selectedLocation = location
    }

    func reset() {
        results = []
        selectedLocation = nil
        statusMessage = nil
        errorMessage = nil
    }
}

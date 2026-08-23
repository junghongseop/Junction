//
//  SearchViewModel.swift
//  DriveInGyeongbuk
//

import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String
    @Published private(set) var results: [NaverLocation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: NaverLocationSearchServicing

    init(initialQuery: String = "",
         service: NaverLocationSearchServicing? = nil) {
        query = initialQuery
        self.service = service ?? NaverLocationSearchService()
    }

    var canSearch: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func search() async {
        guard canSearch else {
            results = []
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            results = try await service.search(query: query, display: 5)
        } catch {
            results = []
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clear() {
        query = ""
        results = []
        errorMessage = nil
    }

    /// 지역 검색은 `영천시청`을 기관 자체보다 상호명에 "영천시청점"이 붙은 가게로
    /// 돌려줄 때가 있다. 데모는 검증된 공식 주소 좌표를 결과 맨 위에 고정해 엉뚱한
    /// 상점을 목적지로 선택하지 않게 한다.
    @discardableResult
    func ensureDemoDestinationResult() -> NaverLocation {
        let destination = DemoDriveLocation.destination
        results.removeAll { $0.coordinate.distance(to: destination.coordinate) < 5 }
        results.insert(destination, at: 0)
        errorMessage = nil
        return destination
    }
}

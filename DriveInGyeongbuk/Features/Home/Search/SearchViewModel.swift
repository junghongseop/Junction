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
}

//
//  SearchFilterHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 3/4/25.
//

import AidokuRunner
import SwiftUI

struct SearchFilterHeaderView: View {
    let source: AidokuRunner.Source

    @Binding var filters: [AidokuRunner.Filter]?
    @Binding var search: String
    @Binding var enabledFilters: [FilterValue]
    @Binding var filtersEmpty: Bool

    var onFilterButtonClick: (() -> Void)?

    @State private var error: Error?

    var body: some View {
        Group {
            if let error {
                let text = error.aidokuDescription()
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else if let filters {
                if filters.isEmpty {
                    EmptyView()
                } else {
                    FilterHeaderView(
                        sourceKey: source.key,
                        filters: filters,
                        search: $search,
                        enabledFilters: $enabledFilters,
                        onFilterButtonClick: onFilterButtonClick
                    )
                }
            } else {
                ProgressView().progressViewStyle(.circular)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("refresh-filters"))) { _ in
            error = nil
            Task {
                await loadFilters()
            }
        }
        .task {
            guard filters == nil else { return }
            await self.loadFilters()
        }
    }

    func loadFilters() async {
        do {
            filters = try await source.getSearchFilters()
            filtersEmpty = filters?.isEmpty ?? true
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }
}

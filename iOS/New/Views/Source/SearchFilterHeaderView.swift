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
    @Binding var enabledFilters: [FilterValue]
    @Binding var filtersEmpty: Bool

    var onFilterButtonClick: (() -> Void)?

    @State private var error: Error?

    var body: some View {
        Group {
            if let error {
                let text = if let error = error as? SourceError {
                    switch error {
                        case .missingResult:
                            NSLocalizedString("NO_RESULT")
                        case .unimplemented:
                            NSLocalizedString("UNIMPLEMENTED")
                        case .networkError:
                            NSLocalizedString("NETWORK_ERROR")
                        case .message(let string):
                            NSLocalizedString(string)
                    }
                } else if error is DecodingError {
                    NSLocalizedString("DECODING_ERROR")
                } else {
                    NSLocalizedString("UNKNOWN_ERROR")
                }
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else if let filters {
                if filters.isEmpty {
                    EmptyView()
                } else {
                    FilterHeaderView(
                        filters: filters,
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
        .padding(.top, {
            if #available(iOS 26.0, *) {
                12
            } else {
                0
            }
        }())
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

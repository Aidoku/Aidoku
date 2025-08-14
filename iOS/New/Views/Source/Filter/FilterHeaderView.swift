//
//  FilterHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 9/17/23.
//

import AidokuRunner
import SwiftUI

struct FilterHeaderView: View {
    let filters: [AidokuRunner.Filter]
    @Binding var enabledFilters: [FilterValue]
    let onFilterButtonClick: (() -> Void)?

    @State private var sortedFilters: [AidokuRunner.Filter]
    @State private var showingSheet = false

    init(
        filters: [AidokuRunner.Filter],
        enabledFilters: Binding<[FilterValue]>,
        onFilterButtonClick: (() -> Void)? = nil
    ) {
        self.filters = filters
        self._enabledFilters = enabledFilters
        self.onFilterButtonClick = onFilterButtonClick

        // sort filters by moving the enabled filters to the front
        var enabled: [AidokuRunner.Filter] = []
        var disabled: [AidokuRunner.Filter] = []

        for filter in filters {
            if enabledFilters.wrappedValue.contains(where: { $0.id == filter.id }) {
                enabled.append(filter)
            } else {
                disabled.append(filter)
            }
        }

        enabled.append(contentsOf: disabled)
        self._sortedFilters = State(initialValue: enabled)
    }

    private var filterCount: Int {
        enabledFilters
            .map {
                switch $0 {
                    case .text, .sort, .check, .select, .range: 1
                    case let .multiselect(_, included, excluded):
                        included.count + excluded.count
                }
            }
            .reduce(0, +)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterSheetButton

                ForEach(sortedFilters, id: \.self) { filter in
                    if !(filter.hideFromHeader ?? false) {
                        switch filter.value {
                            case .sort:
                                SortFilterView(filter: filter, enabledFilters: $enabledFilters)
                            case let .check(_, _, defaultValue):
                                // if check filter has a default value then hide it from the list
                                // we don't want it to appear as enabled when the filters are reset
                                if defaultValue == nil {
                                    CheckFilterView(filter: filter, enabledFilters: $enabledFilters)
                                }
                            case .select:
                                SelectFilterView(filter: filter, enabledFilters: $enabledFilters)
                            case .multiselect:
                                MultiSelectFilterView(filter: filter, enabledFilters: $enabledFilters)
                            default:
                                EmptyView()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .animation(.easeInOut, value: enabledFilters)
        }
        .scrollClipDisabledPlease()
        .animation(.default, value: sortedFilters)
        .padding(.top, -11)
        .sheet(isPresented: $showingSheet) {
            FilterListSheetView(
                filters: filters,
                showResetButton: true,
                enabledFilters: $enabledFilters
            )
        }
        .onChange(of: enabledFilters) { _ in
            sortFilters()
        }
    }

    var filterSheetButton: some View {
        Button {
            if let onFilterButtonClick {
                onFilterButtonClick()
            } else {
                showingSheet = true
            }
        } label: {
            let label = HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                    .opacity(0.6)
                    .foregroundColor(.primary)
                    .font(.footnote.weight(.medium))

                if !enabledFilters.isEmpty {
                    FilterBadgeView(count: filterCount)
                }
            }
            .frame(height: 18)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .font(.caption.weight(.medium))

            if #available(iOS 26.0, *) {
                if enabledFilters.isEmpty {
                    label.glassEffect(.regular, in: .circle)
                } else {
                    label.glassEffect(.regular, in: .capsule)
                }
            } else {
                label
                    .background(
                        Group {
                            if enabledFilters.isEmpty {
                                Circle()
                            } else {
                                // allow space for the badge
                                RoundedRectangle(cornerRadius: 100)
                            }
                        }
                            .foregroundColor(.init(uiColor: .secondarySystemFill))
                    )
                    .overlay {
                        if enabledFilters.isEmpty {
                            Circle()
                                .stroke(Color(uiColor: .tertiarySystemFill), style: .init(lineWidth: 1))
                        } else {
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(Color(uiColor: .tertiarySystemFill), style: .init(lineWidth: 1))
                        }
                    }
            }
        }
    }

    func sortFilters() {
        var enabled: [AidokuRunner.Filter] = []
        var disabled: [AidokuRunner.Filter] = []

        for filter in filters {
            if enabledFilters.contains(where: { $0.id == filter.id }) {
                enabled.append(filter)
            } else {
                disabled.append(filter)
            }
        }

        enabled.append(contentsOf: disabled)

        sortedFilters = enabled
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var enabledFilters: [FilterValue] = []
    return FilterHeaderView(
        filters: [
            .init(
                id: "text",
                title: "Text",
                value: .text(placeholder: "Placeholder")
            ),
            .init(
                id: "sort",
                title: "Sort",
                value: .sort(
                    canAscend: true,
                    options: ["Latest", "Popular"],
                    defaultValue: nil
                )
            ),
            .init(
                id: "select",
                title: "Select",
                value: .select(
                    .init(
                        usesTagStyle: false,
                        options: ["Option 1", "Option 2"],
                        defaultValue: nil
                    )
                )
            ),
            .init(
                id: "select2",
                title: "Select 2",
                value: .select(
                    .init(
                        usesTagStyle: true,
                        options: ["Option 1", "Option 2"],
                        defaultValue: nil
                    )
                )
            ),
            .init(
                id: "multi-select",
                title: "Multi Select",
                value: .multiselect(.init(
                    canExclude: true,
                    options: ["Option 1", "Option 2"],
                    ids: nil
                ))
            ),
            .init(
                id: "genre",
                title: "Genre",
                hideFromHeader: true,
                value: .multiselect(.init(
                    isGenre: true,
                    canExclude: true,
                    options: ["Option 1", "Option 2"],
                    ids: nil
                ))
            ),
            .init(
                id: "check",
                title: "Check",
                value: .check(
                    name: nil,
                    canExclude: true,
                    defaultValue: nil
                )
            ),
            .init(
                id: "note",
                title: nil,
                value: .note("This is a note.")
            )
        ],
        enabledFilters: $enabledFilters
    )
}

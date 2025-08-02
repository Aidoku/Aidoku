//
//  FilterListSheetView.swift
//  Aidoku
//
//  Created by Skitty on 12/29/23.
//

import AidokuRunner
import SwiftUI

struct FilterListSheetView: View {
    let filters: [AidokuRunner.Filter]
    var showResetButton = false

    @Binding var enabledFilters: [FilterValue]

    @State private var newEnabledFilters: [FilterValue]
    @State private var showConfirm = false
    @State private var discardChanges = false

    @Environment(\.dismiss) private var dismiss

    init(
        filters: [AidokuRunner.Filter],
        showResetButton: Bool = false,
        enabledFilters: Binding<[FilterValue]>
    ) {
        self.filters = filters
        self.showResetButton = showResetButton
        self._enabledFilters = enabledFilters
        self._newEnabledFilters = State(initialValue: enabledFilters.wrappedValue)
    }

    var body: some View {
        PlatformNavigationStack {
            let scrollView = ScrollView(.vertical) {
                FilterListView(filters: filters, enabledFilters: $newEnabledFilters)
            }
            .navigationTitle(NSLocalizedString("FILTERS"))
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .confirmationDialog(
                NSLocalizedString("CANCEL_CONFIRM"),
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("DISCARD_CHANGES"), role: .destructive) {
                    discardChanges = true
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("CANCEL_CONFIRM_TEXT"))
            }
            .onDisappear {
                guard !discardChanges, newEnabledFilters != enabledFilters else { return }
                enabledFilters = newEnabledFilters
            }

        
            scrollView
                .toolbar {
                    toolbarContent
                }
        
        }
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(NSLocalizedString("CANCEL")) {
                if newEnabledFilters == enabledFilters {
                    dismiss()
                } else {
                    showConfirm = true
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(NSLocalizedString("APPLY")) {
                dismiss()
            }
            .font(.body.weight(.medium))
        }

        ToolbarItem(placement: .bottomBar) {
            if showResetButton {
            
                HStack {
                    Button(NSLocalizedString("RESET")) {
                        newEnabledFilters = []
                        dismiss()
                    }
                    Spacer()
                }
            
            }
        }
    }
}

private struct FilterListView: View {
    let filters: [AidokuRunner.Filter]
    var showTitles = true

    @Binding var enabledFilters: [FilterValue]

    @State private var text: [String: String]
    @State private var includedOptions: [String: [String]]
    @State private var excludedOptions: [String: [String]]
    @State private var selectedOptions: [String: String]
    @State private var selectedIndexes: [String: Int]
    @State private var ascending: [String: Bool]

    init(filters: [AidokuRunner.Filter], showTitles: Bool = true, enabledFilters: Binding<[FilterValue]>) {
        self.filters = filters
        self.showTitles = showTitles
        self._enabledFilters = enabledFilters

        var text: [String: String] = [:]
        var includedOptions: [String: [String]] = [:]
        var excludedOptions: [String: [String]] = [:]
        var selectedOptions: [String: String] = [:]
        var selectedIndexes: [String: Int] = [:]
        var ascending: [String: Bool] = [:]
        for filter in enabledFilters.wrappedValue {
            switch filter {
                case let .text(id, value):
                    text[id] = value
                case .sort(let value):
                    selectedIndexes[value.id] = Int(value.index)
                    ascending[value.id] = value.ascending
                case let .check(id, value):
                    selectedIndexes[id] = value
                case let .select(id, value):
                    selectedOptions[id] = value
                case let .multiselect(id, included, excluded):
                    includedOptions[id] = included
                    excludedOptions[id] = excluded
            }
        }
        self._text = State(initialValue: text)
        self._includedOptions = State(initialValue: includedOptions)
        self._excludedOptions = State(initialValue: excludedOptions)
        self._selectedOptions = State(initialValue: selectedOptions)
        self._selectedIndexes = State(initialValue: selectedIndexes)
        self._ascending = State(initialValue: ascending)
    }

    var body: some View {
        VStack(spacing: 22) {
            ForEach(Array(filters.enumerated()), id: \.offset) { _, filter in
                VStack(spacing: 6) {
                    switch filter.value {
                        case let .text(placeholder):
                            if showTitles {
                                titleView(filter.title)
                            }
                            Group {
                                if #available(iOS 16.0, *) {
                                    TextField(
                                        "",
                                        text: textBinding(for: filter.id),
                                        prompt: Text(placeholder ?? "").foregroundColor(.gray)
                                    )
                                } else {
                                    TextField(placeholder ?? "", text: textBinding(for: filter.id))
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill)))
                            .padding(.horizontal)

                        case let .sort(_, _, defaultValue):
                            if showTitles {
                                titleView(filter.title ?? NSLocalizedString("SORT"))
                            }
                            SortFilterGroupView(
                                filter: filter,
                                selectedOption: selectedIndexBinding(
                                    for: filter.id,
                                    default: defaultValue?.index ?? 0
                                ),
                                ascending: ascendingBinding(
                                    for: filter.id,
                                    default: defaultValue?.ascending ?? false
                                )
                            )
                            .padding(.horizontal)

                        case let .check(_, _, defaultValue):
                            if showTitles {
                                titleView(filter.title)
                            }
                            CheckFilterGroupView(
                                filter: filter,
                                state: selectedIndexBinding(
                                    for: filter.id,
                                    default: defaultValue.map({ $0 ? 1 : 2 }) ?? 0
                                )
                            )

                        case let .select(value):
                            if showTitles {
                                titleView(filter.title)
                            }
                            SelectFilterGroupView(
                                filter: filter,
                                selectedOption: selectedOptionBinding(
                                    for: filter.id,
                                    default: value.resolvedDefaultValue
                                )
                            )

                        case let .multiselect(value):
                            if showTitles {
                                titleView(filter.title)
                            }
                            MultiSelectFilterGroupView(
                                filter: filter,
                                includedOptions: includedOptionsBinding(for: filter.id, default: value.defaultIncluded ?? []),
                                excludedOptions: excludedOptionsBinding(for: filter.id, default: value.defaultExcluded ?? [])
                            )

                        case .note(let text):
                            Text(text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal)
                    }
                }
            }
        }
        .onChange(of: includedOptions) { _ in
            updateMultiSelectFilters()
        }
        .onChange(of: excludedOptions) { _ in
            updateMultiSelectFilters()
        }
        .onChange(of: selectedIndexes) { _ in
            updateSortFilters()
            updateCheckFilters()
        }
        .onChange(of: selectedOptions) { _ in
            updateSelectFilters()
        }
        .onChange(of: ascending) { _ in
            updateSortFilters()
        }
        .onChange(of: text) { _ in
            updateTextFilters()
        }
    }

    private func titleView(_ title: String?) -> some View {
        HStack {
            Text(title ?? "")
                .font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal)
    }

    private func updateMultiSelectFilters() {
        let ids = Set(Array(includedOptions.keys) + Array(excludedOptions.keys))
        for id in ids {
            guard
                let filter = filters.first(where: { $0.id == id }),
                case let .multiselect(value) = filter.value
            else { continue }

            let included = includedOptions[id, default: value.defaultIncluded ?? []]
            let excluded = excludedOptions[id, default: value.defaultExcluded ?? []]
            let isDefault = included == (value.defaultIncluded ?? []) && excluded == (value.defaultExcluded ?? [])
            let filterValue = FilterValue.multiselect(id: id, included: included, excluded: excluded)

            if let index = enabledFilters.firstIndex(where: { $0.id == filter.id }) {
                if isDefault {
                    enabledFilters.remove(at: index)
                } else {
                    enabledFilters[index] = filterValue
                }
            } else if !isDefault {
                enabledFilters.append(filterValue)
            }
        }
    }

    private func updateSortFilters() {
        let ids = Set(Array(selectedIndexes.keys) + Array(ascending.keys))
        for id in ids {
            guard
                let filter = filters.first(where: { $0.id == id }),
                case let .sort(_, _, defaultValue) = filter.value
            else { continue }
            let index = selectedIndexes[id] ?? defaultValue?.index
            let ascending = ascending[id]
            let isDefault = index == defaultValue?.index && ascending == defaultValue?.ascending
            if let filterIndex = enabledFilters.firstIndex(where: { $0.id == id }) {
                if isDefault {
                    enabledFilters.remove(at: filterIndex)
                } else if case .sort(let value) = enabledFilters[filterIndex] {
                    let newValue = SortFilterValue(
                        id: value.id,
                        index: index ?? Int(value.index),
                        ascending: ascending ?? value.ascending
                    )
                    enabledFilters[filterIndex] = .sort(newValue)
                }
            } else if !isDefault {
                enabledFilters.append(.sort(.init(id: id, index: index ?? 0, ascending: ascending ?? false)))
            }
        }
    }

    private func updateTextFilters() {
        let ids = text.keys
        for id in ids {
            guard
                let filter = filters.first(where: { $0.id == id }),
                case .text = filter.value
            else { continue }

            let value = text[id] ?? ""

            if let filterIndex = enabledFilters.firstIndex(where: { $0.id == id }) {
                if value.isEmpty {
                    enabledFilters.remove(at: filterIndex)
                } else {
                    enabledFilters[filterIndex] = .text(id: id, value: value)
                }
            } else if !value.isEmpty {
                enabledFilters.append(.text(id: id, value: value))
            }
        }
    }

    private func updateCheckFilters() {
        let ids = selectedIndexes.keys
        for id in ids {
            guard
                let filter = filters.first(where: { $0.id == id }),
                case let .check(_, _, defaultValue) = filter.value
            else { continue }

            let defaultIndex = defaultValue.map({ $0 ? 1 : 2 }) ?? 0
            let value = selectedIndexes[id, default: defaultIndex]
            let isDefault = value == defaultIndex
            let filterValue = FilterValue.check(id: id, value: value)

            if let filterIndex = enabledFilters.firstIndex(where: { $0.id == id }) {
                if isDefault {
                    enabledFilters.remove(at: filterIndex)
                } else {
                    enabledFilters[filterIndex] = filterValue
                }
            } else if !isDefault {
                enabledFilters.append(filterValue)
            }
        }
    }

    private func updateSelectFilters() {
        let ids = selectedOptions.keys
        for id in ids {
            guard
                let filter = filters.first(where: { $0.id == id }),
                case let .select(selectFilter) = filter.value
            else { continue }

            let value = selectedOptions[id, default: selectFilter.resolvedDefaultValue]
            let isDefault = value == selectFilter.resolvedDefaultValue
            let filterValue = FilterValue.select(id: filter.id, value: value)

            if let index = enabledFilters.firstIndex(where: { $0.id == filter.id }) {
                if isDefault {
                    enabledFilters.remove(at: index)
                } else {
                    enabledFilters[index] = filterValue
                }
            } else if !isDefault {
                enabledFilters.append(filterValue)
            }
        }
    }

    private func textBinding(for id: String) -> Binding<String> {
        Binding(
            get: { text[id, default: ""] },
            set: { text[id] = $0 }
        )
    }

    private func includedOptionsBinding(for id: String, default def: [String] = []) -> Binding<[String]> {
        Binding(
            get: { includedOptions[id, default: def] },
            set: { includedOptions[id] = $0 }
        )
    }

    private func excludedOptionsBinding(for id: String, default def: [String] = []) -> Binding<[String]> {
        Binding(
            get: { excludedOptions[id, default: def] },
            set: { excludedOptions[id] = $0 }
        )
    }

    private func selectedOptionBinding(for id: String, default def: String) -> Binding<String> {
        Binding(
            get: { selectedOptions[id, default: def] },
            set: { selectedOptions[id] = $0 }
        )
    }

    private func selectedIndexBinding(for id: String, default def: Int) -> Binding<Int> {
        Binding(
            get: { selectedIndexes[id, default: def] },
            set: { selectedIndexes[id] = $0 }
        )
    }

    private func ascendingBinding(for id: String, default def: Bool) -> Binding<Bool> {
        Binding(
            get: { ascending[id, default: def] },
            set: { ascending[id] = $0 }
        )
    }
}

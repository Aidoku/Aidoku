//
//  FilterListSheetView.swift
//  Aidoku
//
//  Created by Skitty on 12/29/23.
//

import AidokuRunner
import SwiftUI

struct FilterListSheetView: View {
    let sourceKey: String?
    let filters: [AidokuRunner.Filter]

    @Binding var search: String
    @Binding var enabledFilters: [FilterValue]

    @State private var newSearch: String?
    @State private var newEnabledFilters: [FilterValue]
    @State private var savedSearches: [SavedSearch]
    @State private var showConfirm = false
    @State private var showSaveErrorAlert = false
    @State private var discardChanges = false

    @Environment(\.dismiss) private var dismiss

    init(
        sourceKey: String? = nil,
        filters: [AidokuRunner.Filter],
        search: Binding<String>,
        enabledFilters: Binding<[FilterValue]>
    ) {
        self.sourceKey = sourceKey
        self.filters = filters
        self._search = search
        self._enabledFilters = enabledFilters
        self._newEnabledFilters = State(initialValue: enabledFilters.wrappedValue)

        if let sourceKey {
            let data = UserDefaults.standard.data(forKey: "\(sourceKey).savedSearches")
            let decodedSearches = data.flatMap { try? JSONDecoder().decode([SavedSearch].self, from: $0) }
            self._savedSearches = State(initialValue: decodedSearches ?? [])
        } else {
            self._savedSearches = State(initialValue: [])
        }
    }

    var body: some View {
        PlatformNavigationStack {
            let scrollView = ScrollView(.vertical) {
                FilterListView(
                    filters: filters,
                    newSearch: $newSearch,
                    enabledFilters: $newEnabledFilters,
                    savedSearches: $savedSearches
                )
            }
            .scrollDismissesKeyboardInteractively()
            .navigationTitle(NSLocalizedString("FILTERS"))
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .confirmationDialogOrAlert(
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
            .alert(NSLocalizedString("SAVE_SEARCH_FAIL"), isPresented: $showSaveErrorAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("SAVE_SEARCH_FAIL_INFO"))
            }
            .onDisappear {
                saveSavedSearches()
                guard !discardChanges, newEnabledFilters != enabledFilters || newSearch != nil else { return }
                if let newSearch {
                    search = newSearch
                }
                enabledFilters = newEnabledFilters
            }

            if #available(iOS 26.0, *) {
                scrollView
                    .toolbar {
                        toolbarContentiOS26
                    }
            } else {
                scrollView
                    .toolbar {
                        toolbarContentiOS18
                    }
            }
        }
    }

    @ToolbarContentBuilder
    var commonToolbarContent: some ToolbarContent {
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
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        commonToolbarContent

        ToolbarItem(placement: .bottomBar) {
            Button(NSLocalizedString("RESET")) {
                newEnabledFilters = []
                dismiss()
            }
        }

        ToolbarSpacer(.flexible, placement: .bottomBar)

        if sourceKey != nil {
            ToolbarItem(placement: .bottomBar) {
                Button(NSLocalizedString("SAVE")) {
                    promptSearchSave()
                }
            }
        }
    }

    @ToolbarContentBuilder
    var toolbarContentiOS18: some ToolbarContent {
        commonToolbarContent

        ToolbarItem(placement: .bottomBar) {
            HStack {
                Button(NSLocalizedString("RESET")) {
                    newEnabledFilters = []
                    dismiss()
                }
                Spacer()
                if sourceKey != nil {
                    Button(NSLocalizedString("SAVE")) {
                        promptSearchSave()
                    }
                }
            }
        }
    }

    func promptSearchSave() {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("NAME_SAVED_SEARCH"),
            message: NSLocalizedString("NAME_SAVED_SEARCH_INFO"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    guard !savedSearches.contains(where: { $0.name == text }) else {
                        showSaveErrorAlert = true
                        return
                    }
                    let savedSearch = SavedSearch(
                        name: text,
                        search: newSearch ?? search,
                        filters: newEnabledFilters
                    )
                    savedSearches.append(savedSearch)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("SAVED_SEARCH_NAME")
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
    }

    func saveSavedSearches() {
        guard let sourceKey else { return }
        let key = "\(sourceKey).savedSearches"
        if savedSearches.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            let data = try? JSONEncoder().encode(savedSearches)
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private struct FilterListView: View {
    let filters: [AidokuRunner.Filter]
    let showTitles: Bool

    @Binding var newSearch: String?
    @Binding var enabledFilters: [FilterValue]
    @Binding var savedSearches: [SavedSearch]

    @State private var text: [String: String]
    @State private var from: [String: Float]
    @State private var to: [String: Float]
    @State private var includedOptions: [String: [String]]
    @State private var excludedOptions: [String: [String]]
    @State private var selectedOptions: [String: String]
    @State private var selectedIndexes: [String: Int]
    @State private var ascending: [String: Bool]

    @State private var search: [String: String] = [:]
    @State private var hasError: [String: Bool] = [:]

    @FocusState private var fieldFocused: String?

    @Environment(\.dismiss) var dismiss

    init(
        filters: [AidokuRunner.Filter],
        showTitles: Bool = true,
        newSearch: Binding<String?>,
        enabledFilters: Binding<[FilterValue]>,
        savedSearches: Binding<[SavedSearch]>
    ) {
        self.filters = filters
        self.showTitles = showTitles
        self._newSearch = newSearch
        self._enabledFilters = enabledFilters
        self._savedSearches = savedSearches

        var text: [String: String] = [:]
        var from: [String: Float] = [:]
        var to: [String: Float] = [:]
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
                case let .range(id, fromValue, toValue):
                    from[id] = fromValue
                    to[id] = toValue
            }
        }
        self._text = State(initialValue: text)
        self._from = State(initialValue: from)
        self._to = State(initialValue: to)
        self._includedOptions = State(initialValue: includedOptions)
        self._excludedOptions = State(initialValue: excludedOptions)
        self._selectedOptions = State(initialValue: selectedOptions)
        self._selectedIndexes = State(initialValue: selectedIndexes)
        self._ascending = State(initialValue: ascending)
    }

    var body: some View {
        VStack(spacing: 22) {
            savedSearchesView

            ForEach(filters.indices, id: \.self) { index in
                let filter = filters[index]
                VStack(spacing: 6) {
                    switch filter.value {
                        case let .text(placeholder):
                            if showTitles {
                                titleView(filter.title)
                            }
                            TextFieldWrapper {
                                let textBinding = textBinding(for: filter.id)
                                TextField(placeholder ?? "", text: textBinding)
                                    .autocorrectionDisabled()
                                if !textBinding.wrappedValue.isEmpty {
                                    ClearFieldButton {
                                        textBinding.wrappedValue = ""
                                    }
                                }
                            }
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
                                let shouldShowSearch = value.usesTagStyle && value.options.count >= 15
                                titleView(filter.title, searchId: shouldShowSearch ? filter.id : nil)
                            }
                            let searchText = search[filter.id]
                            if searchText != nil {
                                searchField(id: filter.id)
                            }
                            SelectFilterGroupView(
                                filter: filter,
                                searchText: searchText,
                                selectedOption: selectedOptionBinding(
                                    for: filter.id,
                                    default: value.resolvedDefaultValue
                                )
                            )

                        case let .multiselect(value):
                            if showTitles {
                                let shouldShowSearch = value.usesTagStyle && value.options.count >= 15
                                titleView(filter.title, searchId: shouldShowSearch ? filter.id : nil)
                            }
                            let searchText = search[filter.id]
                            if searchText != nil {
                                searchField(id: filter.id)
                            }
                            MultiSelectFilterGroupView(
                                filter: filter,
                                searchText: searchText,
                                includedOptions: includedOptionsBinding(for: filter.id, default: value.defaultIncluded ?? []),
                                excludedOptions: excludedOptionsBinding(for: filter.id, default: value.defaultExcluded ?? [])
                            )

                        case .note(let text):
                            Text(text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal)

                        case let .range(min, max, decimal):
                            if showTitles {
                                titleView(filter.title)
                            }
                            rangeFilterView(filter: filter, min: min, max: max, decimal: decimal)
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

    @ViewBuilder
    var savedSearchesView: some View {
        if !savedSearches.isEmpty {
            VStack(spacing: 6) {
                titleView(NSLocalizedString("SAVED_SEARCHES"))

                VStack(spacing: 0) {
                    ForEach(savedSearches, id: \.name) { savedSearch in
                        Button {
                            newSearch = savedSearch.search
                            enabledFilters = savedSearch.filters
                            dismiss()
                        } label: {
                            HStack {
                                Text(savedSearch.name)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    if let index = savedSearches.firstIndex(where: { $0.name == savedSearch.name }) {
                                        withAnimation {
                                            _ = savedSearches.remove(at: index)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                        }
                        .buttonStyle(SelectHighlightButtonStyle())
                    }
                }
            }
        }
    }

    private func titleView(_ title: String?, searchId: String? = nil) -> some View {
        HStack {
            Text(title ?? "")
                .font(.title3.weight(.semibold))
            Spacer()
            if let searchId {
                let isSearching = search[searchId] != nil
                Button {
                    withAnimation {
                        if isSearching {
                            search[searchId] = nil
                        } else {
                            search[searchId] = ""
                            fieldFocused = searchId
                        }
                    }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func searchField(id: String) -> some View {
        let searchText = search[id] ?? ""
        textField {
            HStack {
                TextField(NSLocalizedString("SEARCH"), text: searchBinding(for: id))
                    .focused($fieldFocused, equals: id)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    ClearFieldButton {
                        search[id] = ""
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 2)
    }

    private func textField<Content: View>(content: @escaping () -> Content) -> some View {
        Group {
            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
        )
    }

    private func rangeFilterView(filter: AidokuRunner.Filter, min: Float?, max: Float?, decimal: Bool) -> some View {
        HStack {
            TextFieldWrapper(hasError: hasError[filter.id + ".from", default: false]) {
                let value = fromBinding(for: filter.id)
                TextField(NSLocalizedString("RANGE_FROM"), value: value, format: .number)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                if value.wrappedValue != nil {
                    ClearFieldButton {
                        value.wrappedValue = nil
                    }
                }
            }
            TextFieldWrapper(hasError: hasError[filter.id + ".to", default: false]) {
                let value = toBinding(for: filter.id)
                TextField(NSLocalizedString("RANGE_TO"), value: value, format: .number)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                if value.wrappedValue != nil {
                    ClearFieldButton {
                        value.wrappedValue = nil
                    }
                }
            }
        }
        .padding(.horizontal)
        .onChange(of: from[filter.id]) { value in
            let error = if let value {
                if let min, value < min {
                    true
                } else if let toValue = to[filter.id], value > toValue {
                    true
                } else {
                    false
                }
            } else {
                false
            }
            hasError[filter.id + ".from"] = error
            if !error {
                updateRangeFilter(id: filter.id)
            }
        }
        .onChange(of: to[filter.id]) { value in
            let error = if let value {
                if let max, value > max {
                    true
                } else if let fromValue = from[filter.id], value < fromValue {
                    true
                } else {
                    false
                }
            } else {
                false
            }
            hasError[filter.id + ".to"] = error
            if !error {
                updateRangeFilter(id: filter.id)
            }
        }
    }
}

extension FilterListView {
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

    private func updateRangeFilter(id: String) {
        guard
            let filter = filters.first(where: { $0.id == id }),
            case .range = filter.value
        else { return }

        let fromValue = from[id]
        let toValue = to[id]
        let filterValue = FilterValue.range(id: id, from: fromValue, to: toValue)

        if let filterIndex = enabledFilters.firstIndex(where: { $0.id == id }) {
            if fromValue == nil && toValue == nil {
                enabledFilters.remove(at: filterIndex)
            } else {
                enabledFilters[filterIndex] = filterValue
            }
        } else if fromValue != nil || toValue != nil {
            enabledFilters.append(filterValue)
        }
    }
}

extension FilterListView {
    private func textBinding(for id: String) -> Binding<String> {
        Binding(
            get: { text[id, default: ""] },
            set: { text[id] = $0 }
        )
    }

    private func fromBinding(for id: String) -> Binding<Float?> {
        Binding(
            get: { from[id] },
            set: { from[id] = $0 }
        )
    }

    private func toBinding(for id: String) -> Binding<Float?> {
        Binding(
            get: { to[id] },
            set: { to[id] = $0 }
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

    private func searchBinding(for id: String) -> Binding<String> {
        Binding(
            get: { search[id, default: ""] },
            set: { search[id] = $0 }
        )
    }
}

//
//  MultiSelectFilterView.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import AidokuRunner
import SwiftUI

struct MultiSelectFilterView: View {
    let filter: AidokuRunner.Filter

    @Binding var enabledFilters: [FilterValue]

    private let multiSelectFilter: MultiSelectFilter

    @State private var showingSheet = false
    @State private var includedOptions: [String]
    @State private var excludedOptions: [String]

    init(filter: AidokuRunner.Filter, enabledFilters: Binding<[FilterValue]>) {
        self.filter = filter
        self._enabledFilters = enabledFilters

        if case let .multiselect(filter) = filter.value {
            self.multiSelectFilter = filter
        } else {
            fatalError("invalid filter type")
        }

        let defaultIncluded = multiSelectFilter.defaultIncluded ?? []
        let defaultExcluded = multiSelectFilter.defaultExcluded ?? []

        if
            let enabledValue = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case let .multiselect(_, included, excluded) = enabledValue
        {
            self._includedOptions = State(initialValue: included)
            self._excludedOptions = State(initialValue: excluded)
        } else {
            self._includedOptions = State(initialValue: defaultIncluded)
            self._excludedOptions = State(initialValue: defaultExcluded)
        }
    }

    var isDefault: Bool {
        includedOptions == (multiSelectFilter.defaultIncluded ?? [])
            && excludedOptions == (multiSelectFilter.defaultExcluded ?? [])
    }

    var body: some View {
        Group {
            let label = FilterLabelView(
                name: filter.title ?? "",
                badgeCount: isDefault ? 0 : includedOptions.count + excludedOptions.count,
                chevron: true
            )
            Menu {
                ForEach(Array(multiSelectFilter.options.enumerated()), id: \.offset) { offset, option in
                    let id = multiSelectFilter.ids?[safe: offset] ?? option
                    Button {
                        toggle(option: id)
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if includedOptions.contains(id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            } else if multiSelectFilter.canExclude, excludedOptions.contains(id) {
                                Image(systemName: "xmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } label: {
                label
            }
        }
        .sheet(isPresented: $showingSheet) {
            PlatformNavigationStack {
                ScrollView(.vertical) {
                    MultiSelectFilterGroupView(
                        filter: filter,
                        includedOptions: $includedOptions,
                        excludedOptions: $excludedOptions
                    )
                }
                .navigationTitle(filter.title?.localizedCapitalized ?? "")
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
        .onChange(of: includedOptions) { _ in
            updateFilter()
        }
        .onChange(of: excludedOptions) { _ in
            updateFilter()
        }
        .onChange(of: enabledFilters) { _ in
            if let enabledFilter = enabledFilters.first(where: { $0.id == filter.id }) {
                if case let .multiselect(_, included, excluded) = enabledFilter {
                    includedOptions = included
                    excludedOptions = excluded
                }
            } else {
                includedOptions = multiSelectFilter.defaultIncluded ?? []
                excludedOptions = multiSelectFilter.defaultExcluded ?? []
            }
        }
    }

    func toggle(option: String) {
        if let index = includedOptions.firstIndex(of: option) {
            let result = includedOptions.remove(at: index)
            if multiSelectFilter.canExclude {
                excludedOptions.append(result)
            }
        } else if multiSelectFilter.canExclude, let index = excludedOptions.firstIndex(of: option) {
            excludedOptions.remove(at: index)
        } else {
            includedOptions.append(option)
        }
    }

    func updateFilter() {
        let filterValue = FilterValue.multiselect(id: filter.id, included: includedOptions, excluded: excludedOptions)

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

struct MultiSelectFilterGroupView: View {
    let filter: AidokuRunner.Filter

    @Binding var includedOptions: [String]
    @Binding var excludedOptions: [String]

    private let multiSelectFilter: MultiSelectFilter

    private enum State {
        case normal
        case included
        case excluded
    }

    init(
        filter: AidokuRunner.Filter,
        includedOptions: Binding<[String]>,
        excludedOptions: Binding<[String]>
    ) {
        self.filter = filter
        self._includedOptions = includedOptions
        self._excludedOptions = excludedOptions

        if case let .multiselect(filter) = filter.value {
            self.multiSelectFilter = filter
        } else {
            fatalError("invalid filter type")
        }
    }

    var body: some View {
        Group {
            if multiSelectFilter.usesTagStyle {
                tagBody
            } else {
                listBody
            }
        }
    }

    var tagBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HCollectionGrid(
                rows: min(Int(multiSelectFilter.options.count / 12), 4) + 1,
                verticalSpacing: 8,
                horizontalSpacing: 8,
                Array(multiSelectFilter.options.enumerated()),
                id: \.offset
            ) { offset, option in
                let id = multiSelectFilter.ids?[safe: offset] ?? option
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggle(option: id)
                    }
                } label: {
                    Text(option)
                }
                .buttonStyle(
                    GenreButtonStyle(state: {
                        if includedOptions.contains(id) {
                            multiSelectFilter.canExclude ? .included : .enabled
                        } else if multiSelectFilter.canExclude, excludedOptions.contains(id) {
                            .excluded
                        } else {
                            .normal
                        }
                    }())
                )
            }
            .padding(.horizontal)
        }
        .scrollClipDisabledPlease()
        .padding(.top, 2)
    }

    var listBody: some View {
        VStack(spacing: 0) {
            ForEach(Array(multiSelectFilter.options.enumerated()), id: \.offset) { offset, option in
                let id = multiSelectFilter.ids?[safe: offset] ?? option
                Button {
                    toggle(option: id)
                } label: {
                    HStack {
                        ZStack {
                            let state: State = if includedOptions.contains(id) {
                                .included
                            } else if multiSelectFilter.canExclude, excludedOptions.contains(id) {
                                .excluded
                            } else {
                                .normal
                            }
                            RoundedRectangle(cornerRadius: 5)
                                .fill(state == .normal ? Color(uiColor: .secondarySystemFill) : Color.accentColor)
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 24)
                            if state != .normal {
                                Image(systemName: state == .included ? "checkmark" : "xmark")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 14).weight(.semibold))
                            }
                        }
                        Text(option)
                            .padding(.leading, 1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                }
                .buttonStyle(SelectHighlightButtonStyle())
            }
        }
    }

    func toggle(option: String) {
        if let index = includedOptions.firstIndex(of: option) {
            let result = includedOptions.remove(at: index)
            if multiSelectFilter.canExclude {
                excludedOptions.append(result)
            }
        } else if multiSelectFilter.canExclude, let index = excludedOptions.firstIndex(of: option) {
            excludedOptions.remove(at: index)
        } else {
            includedOptions.append(option)
        }
    }
}

private struct GenreButtonStyle: ButtonStyle {
    var state: State

    enum State {
        case normal
        case enabled
        case included
        case excluded
    }

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = state == .normal ? Color.primary : Color.white
        let backgroundColor = switch state {
            case .normal:
                Color(uiColor: .secondarySystemBackground)
            case .enabled:
                Color.accentColor
            case .included:
                Color.green
            case .excluded:
                Color.red
        }
        return configuration.label
            .font(.callout)
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.7 : 1))
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

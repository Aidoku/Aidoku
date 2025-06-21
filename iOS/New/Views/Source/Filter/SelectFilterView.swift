//
//  SelectFilterView.swift
//  Aidoku
//
//  Created by Skitty on 3/14/24.
//

import AidokuRunner
import SwiftUI

struct SelectFilterView: View {
    let filter: AidokuRunner.Filter

    @Binding var enabledFilters: [FilterValue]

    private let selectFilter: AidokuRunner.SelectFilter

    @State private var showingSheet = false
    @State private var selectedOption: String

    init(filter: AidokuRunner.Filter, enabledFilters: Binding<[FilterValue]>) {
        self.filter = filter
        self._enabledFilters = enabledFilters

        guard case let .select(value) = filter.value else {
            fatalError("invalid filter type")
        }
        self.selectFilter = value

        let initialValue = if
            let enabledFilter = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case let .select(_, value) = enabledFilter
        {
            value
        } else {
            value.resolvedDefaultValue
        }
        self._selectedOption = State(initialValue: initialValue)
    }

    var body: some View {
        Group {
            let label = FilterLabelView(
                name: filter.title ?? "",
                active: selectedOption != selectFilter.resolvedDefaultValue,
                chevron: true
            )
            Menu {
                ForEach(selectFilter.options.indices, id: \.self) { offset in
                    let option = selectFilter.options[offset]
                    let value = selectFilter.ids?[safe: offset] ?? option
                    Button {
                        selectedOption = value
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if selectedOption == value {
                                Image(systemName: "checkmark")
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
                    SelectFilterGroupView(
                        filter: filter,
                        selectedOption: $selectedOption
                    )
                }
                .navigationTitle(filter.title?.localizedCapitalized ?? "")
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
        .onChange(of: selectedOption) { _ in
            updateFilter()
        }
        .onChange(of: enabledFilters) { _ in
            if let enabledFilter = enabledFilters.first(where: { $0.id == filter.id }) {
                if case let .select(_, value) = enabledFilter {
                    selectedOption = value
                }
            } else {
                selectedOption = selectFilter.resolvedDefaultValue
            }
        }
    }

    func updateFilter() {
        let value = selectedOption
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

struct SelectFilterGroupView: View {
    let filter: AidokuRunner.Filter

    @Binding var selectedOption: String

    private let selectFilter: AidokuRunner.SelectFilter

    init(filter: AidokuRunner.Filter, selectedOption: Binding<String>) {
        self.filter = filter
        self._selectedOption = selectedOption

        guard case let .select(value) = filter.value else {
            fatalError("invalid filter type")
        }
        self.selectFilter = value
    }

    var body: some View {
        Group {
            if selectFilter.usesTagStyle {
                tagBody
            } else {
                listBody
            }
        }
    }

    var tagBody: some View {
        WrappingHStack(selectFilter.options.indices, id: \.self) { offset in
            let option = selectFilter.options[offset]
            let value = selectFilter.ids?[safe: offset] ?? option
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedOption = value
                }
            } label: {
                Text(option)
            }
            .buttonStyle(SelectButtonStyle(selected: selectedOption == value))
            .padding([.trailing, .bottom], 8)
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }

    var listBody: some View {
        VStack(spacing: 0) {
            ForEach(selectFilter.options.indices, id: \.self) { offset in
                let option = selectFilter.options[offset]
                let value = selectFilter.ids?[safe: offset] ?? option
                Button {
                    selectedOption = value
                } label: {
                    HStack {
                        ZStack {
                            let selected = selectedOption == value
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? Color.accentColor : Color(uiColor: .secondarySystemFill))
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 24)
                            if selected {
                                Image(systemName: "checkmark")
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
}

private struct SelectButtonStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = selected ? Color.white : Color.primary
        let backgroundColor = selected ? Color.accentColor : Color(uiColor: .secondarySystemBackground)
        return // HStack(spacing: 5) {
            configuration.label
                .font(.callout)
//            if selected {
//                Image(systemName: "checkmark")
//                    .font(.callout.weight(.medium))
//            }
//        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.7 : 1))
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

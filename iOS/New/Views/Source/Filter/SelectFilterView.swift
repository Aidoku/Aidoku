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

    private let usesTagStyle: Bool
    private let options: [String]
    private let defaultValue: Int?

    @State private var showingSheet = false
    @State private var selectedOption: Int

    init(filter: AidokuRunner.Filter, enabledFilters: Binding<[FilterValue]>) {
        self.filter = filter
        self._enabledFilters = enabledFilters

        guard case let .select(_, usesTagStyle, options, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.usesTagStyle = usesTagStyle
        self.options = options
        self.defaultValue = defaultValue

        let initialValue = if
            let enabledFilter = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case let .select(_, value) = enabledFilter
        {
            value
        } else {
            defaultValue ?? 0
        }
        self._selectedOption = State(initialValue: initialValue)
    }

    var body: some View {
        Group {
            let label = FilterLabelView(
                name: filter.title ?? "",
                active: selectedOption != defaultValue ?? 0,
                chevron: true
            )
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                    Button {
                        selectedOption = offset
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if selectedOption == offset {
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
                selectedOption = defaultValue ?? 0
            }
        }
    }

    func updateFilter() {
        let value = selectedOption
        let isDefault = value == (defaultValue ?? 0)
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

    @Binding var selectedOption: Int

    private let usesTagStyle: Bool
    private let options: [String]
    private let defaultValue: Int?

    init(filter: AidokuRunner.Filter, selectedOption: Binding<Int>) {
        self.filter = filter
        self._selectedOption = selectedOption

        guard case let .select(_, usesTagStyle, options, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.usesTagStyle = usesTagStyle
        self.options = options
        self.defaultValue = defaultValue
    }

    var body: some View {
        Group {
            if usesTagStyle {
                tagBody
            } else {
                listBody
            }
        }
    }

    var tagBody: some View {
        WrappingHStack(
            Array(options.enumerated()),
            id: \.offset
        ) { offset, option in
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedOption = offset
                }
            } label: {
                Text(option)
            }
            .buttonStyle(SelectButtonStyle(selected: selectedOption == offset))
            .padding([.trailing, .bottom], 8)
        }
        .padding(.horizontal)
        .padding(.top, 2)
    }

    var listBody: some View {
        VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                Button {
                    selectedOption = offset
                } label: {
                    HStack {
                        ZStack {
                            let selected = selectedOption == offset
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

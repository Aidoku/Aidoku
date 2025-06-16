//
//  SortFilterView.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import AidokuRunner
import SwiftUI

struct SortFilterView: View {
    let filter: AidokuRunner.Filter

    @Binding var enabledFilters: [FilterValue]

    private let canAscend: Bool
    private let options: [String]
    private let defaultValue: AidokuRunner.Filter.SortDefault?

    @State private var selectedOption: Int
    @State private var ascending: Bool

    private var active: Bool {
        (selectedOption != defaultValue?.index ?? 0) || (ascending != defaultValue?.ascending ?? false)
    }

    init(filter: AidokuRunner.Filter, enabledFilters: Binding<[FilterValue]>) {
        self.filter = filter
        self._enabledFilters = enabledFilters

        guard case let .sort(canAscend, options, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.canAscend = canAscend
        self.options = options
        self.defaultValue = defaultValue

        if
            let enabledValue = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case .sort(let value) = enabledValue
        {
            self._selectedOption = State(initialValue: Int(value.index))
            self._ascending = State(initialValue: value.ascending)
        } else {
            self._selectedOption = State(initialValue: defaultValue?.index ?? 0)
            self._ascending = State(initialValue: defaultValue?.ascending ?? false)
        }
    }

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    withAnimation {
                        if selectedOption == index && canAscend {
                            ascending.toggle()
                        } else {
                            selectedOption = index
                            ascending = false
                        }
                    }
                } label: {
                    HStack {
                        Text(option)
                        if selectedOption == index {
                            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            FilterLabelView(
                name: {
                    if selectedOption >= options.count {
                        NSLocalizedString("INVALID")
                    } else if let title = filter.title {
                        "\(title): \(options[selectedOption])"
                    } else {
                        options[selectedOption]
                    }
                }(),
                active: active,
                chevron: true
            )
        }
        .onChange(of: selectedOption) { _ in
            updateFilter()
        }
        .onChange(of: ascending) { _ in
            updateFilter()
        }
        .onChange(of: enabledFilters) { _ in
            if let enabledFilter = enabledFilters.first(where: { $0.id == filter.id }) {
                if case .sort(let value) = enabledFilter {
                    selectedOption = Int(value.index)
                    ascending = value.ascending
                }
            } else {
                selectedOption = defaultValue?.index ?? 0
                ascending = defaultValue?.ascending ?? false
            }
        }
    }

    func updateFilter() {
        if let index = enabledFilters.firstIndex(where: { $0.id == filter.id }) {
            enabledFilters.remove(at: index)
        }
        if active {
            enabledFilters.append(
                FilterValue.sort(.init(
                    id: filter.id,
                    index: selectedOption,
                    ascending: ascending
                ))
            )
        }
    }
}

struct SortFilterGroupView: View {
    let filter: AidokuRunner.Filter

    let canAscend: Bool
    let options: [String]
    let defaultValue: AidokuRunner.Filter.SortDefault?

    @Binding var selectedOption: Int
    @Binding var ascending: Bool

    init(
        filter: AidokuRunner.Filter,
        selectedOption: Binding<Int>,
        ascending: Binding<Bool>
    ) {
        self.filter = filter
        self._selectedOption = selectedOption
        self._ascending = ascending

        guard case let .sort(canAscend, options, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.canAscend = canAscend
        self.options = options
        self.defaultValue = defaultValue
    }

    var body: some View {
        WrappingHStack(
            options.indices,
            id: \.self
        ) { offset in
            let option = options[offset]
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if selectedOption == offset && canAscend {
                        ascending.toggle()
                    } else {
                        selectedOption = offset
                        ascending = false
                    }
                }
            } label: {
                Text(option)
            }
            .buttonStyle(SortButtonStyle(state: {
                if selectedOption == offset {
                    ascending ? .ascending : .descending
                } else {
                    .normal
                }
            }()))
            .padding([.trailing, .bottom], 8)
        }
        .padding(.top, 2)
    }
}

struct SortButtonStyle: ButtonStyle {
    var state: State

    enum State {
        case normal
        case descending
        case ascending
    }

    func makeBody(configuration: Configuration) -> some View {
        let foregroundColor = state == .normal ? Color.primary : Color.white
        let backgroundColor = switch state {
            case .normal:
                Color(uiColor: .secondarySystemBackground)
            case .descending, .ascending:
                Color.accentColor
        }
        return HStack(spacing: 5) {
            configuration.label
                .font(.callout)
            if state != .normal {
                Image(systemName: state == .descending ? "chevron.down" : "chevron.up")
                    .font(.callout.weight(.medium))
                    .padding(state == .descending ? .top : .bottom, 1)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .foregroundStyle(foregroundColor.opacity(configuration.isPressed ? 0.7 : 1))
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

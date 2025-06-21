//
//  CheckFilterView.swift
//  Aidoku
//
//  Created by Skitty on 3/14/24.
//

import AidokuRunner
import SwiftUI

struct CheckFilterView: View {
    let filter: AidokuRunner.Filter

    @Binding var enabledFilters: [FilterValue]

    private let name: String?
    private let canExclude: Bool
    private let defaultValue: Bool?

    @State private var state: Int

    init(filter: AidokuRunner.Filter, enabledFilters: Binding<[FilterValue]>) {
        self.filter = filter
        self._enabledFilters = enabledFilters

        guard case let .check(name, canExclude, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.name = name
        self.canExclude = canExclude
        self.defaultValue = defaultValue

        if
            let enabledValue = enabledFilters.wrappedValue.first(where: { $0.id == filter.id }),
            case .check(_, let value) = enabledValue
        {
            self._state = State(initialValue: value)
        } else {
            self._state = State(initialValue: 0)
        }
    }

    var body: some View {
        Button {
            switch state {
                case 0: state = 1
                case 1: state = canExclude ? 2 : 0
                case 2: state = 0
                default: break
            }
        } label: {
            FilterLabelView(
                name: name ?? filter.title ?? "",
                active: state != 0,
                chevron: false,
                icon: {
                    if canExclude {
                        switch state {
                            case 1: "checkmark"
                            case 2: "xmark"
                            default: nil
                        }
                    } else {
                        nil
                    }
                }()
            )
        }
        .onChange(of: state) { _ in
            updateFilter()
        }
        .onChange(of: enabledFilters) { _ in
            if let enabledFilter = enabledFilters.first(where: { $0.id == filter.id }) {
                if case .check(_, let value) = enabledFilter {
                    state = value
                }
            } else {
                state = 0
            }
        }
    }

    func updateFilter() {
        if let index = enabledFilters.firstIndex(where: { $0.id == filter.id }) {
            enabledFilters.remove(at: index)
        }
        if state != 0 {
            enabledFilters.append(
                FilterValue.check(
                    id: filter.id,
                    value: state
                )
            )
        }
    }
}

struct CheckFilterGroupView: View {
    let filter: AidokuRunner.Filter

    @Binding var state: Int

    private let name: String?
    private let canExclude: Bool
    private let defaultValue: Bool?

    init(filter: AidokuRunner.Filter, state: Binding<Int>) {
        self.filter = filter
        self._state = state

        guard case let .check(name, canExclude, defaultValue) = filter.value else {
            fatalError("invalid filter type")
        }
        self.name = name
        self.canExclude = canExclude
        self.defaultValue = defaultValue
    }

    var body: some View {
        Button {
            switch state {
                case 0: state = 1
                case 1: state = canExclude ? 2 : 0
                case 2: state = 0
                default: break
            }
        } label: {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(state == 0 ? Color(uiColor: .secondarySystemFill) : Color.accentColor)
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: 24)
                    if state == 1 || state == 2 {
                        Image(systemName: state == 1 ? "checkmark" : "xmark")
                            .foregroundStyle(.white)
                            .font(.system(size: 14).weight(.semibold))
                    }
                }
                Text(name ?? filter.title ?? "")
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

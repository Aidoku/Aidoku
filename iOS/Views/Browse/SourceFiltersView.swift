//
//  SourceFiltersView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/18/22.
//

import SwiftUI
import SwiftUIX

class SelectedFilters: ObservableObject {
    @Published var filters: [Filter] = []
}

struct SourceFiltersView: View {
    var filters: [Filter]
    @ObservedObject var selectedFilters: SelectedFilters
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filters.filter { $0.type != .text }) { filter in
                    FilterListCell(filter: filter, selectedFilters: selectedFilters)
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FilterSortCell: View {
    let filter: Filter
    @ObservedObject var selectedFilters: SelectedFilters
    
    var value: SortOption {
        selectedFilters.filters.first { $0.name == filter.name }?.value as? SortOption ?? SortOption(index: 0, name: "", ascending: false)
    }
    
    func setValue(_ option: SortOption) {
        var newArray = selectedFilters.filters.filter { $0.name != filter.name }
        newArray.append(Filter(type: .sort, name: filter.name, value: option))
        selectedFilters.filters = newArray
    }
    
    var body: some View {
        NavigationLink {
            List {
                ForEach(filter.value as? [Filter] ?? []) { subFilter in
                    Button {
                        if let option = subFilter.value as? SortOption {
                            let asc = subFilter.name == value.name && !value.ascending
                            setValue(SortOption(index: option.index, name: option.name, ascending: asc))
                        }
                    } label: {
                        HStack {
                            Text(subFilter.name)
                                .foregroundColor(.label)
                            Spacer()
                            if subFilter.name == value.name {
                                Image(systemName: value.ascending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            }
        } label: {
            Text(filter.name)
        }
    }
}

struct FilterListCell: View {
    let filter: Filter
    @ObservedObject var selectedFilters: SelectedFilters
    
    var selectedValue: Int? {
        selectedFilters.filters.filter({ $0.name == filter.name }).first?.value as? Int
    }
    var canExclude: Bool {
        filter.value as? Bool ?? false
    }
    
    func toggle() {
        var newArray = selectedFilters.filters
        if let value = selectedValue {
            newArray = newArray.filter { $0.name != filter.name }
            if value == 1 && canExclude {
                newArray.append(Filter(type: filter.type, name: filter.name, value: 2))
            }
        } else {
            newArray.append(Filter(type: filter.type, name: filter.name, value: 1))
        }
        selectedFilters.filters = newArray
    }
    
    var body: some View {
        if filter.type == .group {
            NavigationLink {
                List {
                    ForEach((filter.value as? [Filter] ?? []).filter { $0.type != .text }) { subFilter in
                        FilterListCell(filter: subFilter, selectedFilters: selectedFilters)
                    }
                }
            } label: {
                Text(filter.name)
            }
        } else if filter.type == .sort {
            FilterSortCell(filter: filter, selectedFilters: selectedFilters)
        } else if filter.type == .select {
            NavigationLink {
                List {
                    ForEach(filter.value as? [String] ?? [], id: \.self) { option in
                        Button {} label: {
                            HStack {
                                Text(option)
                                    .foregroundColor(.label)
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(filter.name)
            }
        } else if filter.type == .check {
            Button {
                toggle()
            } label: {
                HStack {
                    Text(filter.name)
                        .foregroundColor(.label)
                    Spacer()
                    if let value = selectedValue {
                        Image(systemName: value == 1 ? "checkmark" : "xmark")
                    }
                }
            }
        } else {
            Text(filter.name)
        }
    }
}

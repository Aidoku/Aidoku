//
//  SourceFiltersView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/18/22.
//

import SwiftUI

struct ParsedFilter: Identifiable {
    var id = UUID()
    
    var type: FilterType
    var name: String
    var filter: Filter
    
    var items: [ParsedFilter]?
    
    var currentValue: Int = 0
    
    var boolValue: Bool {
        filter.value as? Bool ?? false
    }
    var defaultIntValue: Int {
        filter.defaultValue as? Int ?? 0
    }
}

struct SourceFiltersView: View {
    
    @Environment(\.presentationMode) var presentationMode
    
    let source: Source
    @Binding var selected: [Filter]
    
    @State var filters: [Filter] = []
    @State var parsedFilters: [ParsedFilter] = []
    @State var selectedFilters: [String: ParsedFilter] = [:]
    
    @State var groupsExpanded: [Bool] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(Array(parsedFilters.enumerated()), id: \.1.id) { i, group in
                    DisclosureGroup(isExpanded: $groupsExpanded[i]) {
                        ForEach(group.items ?? []) { filter in
                            Button {
                                if let index = group.items?.firstIndex(where: { $0.id == filter.id }), let currentValue = parsedFilters[i].items?[index].currentValue {
                                    if filter.type == .sort {
                                        selectedFilters = selectedFilters.filter { $0.value.type != .sort }
                                        group.items?.filter { $0.type == .sort }.indices.forEach { parsedFilters[i].items?[$0].currentValue = 0 }
                                        if filter.boolValue && currentValue == 1 { // can ascend
                                            parsedFilters[i].items?[index].currentValue = 2
                                        } else {
                                            parsedFilters[i].items?[index].currentValue = 1
                                        }
                                        selectedFilters[filter.id.uuidString] = parsedFilters[i].items?[index]
                                    } else if filter.type == .option {
                                        if filter.boolValue && currentValue == 1 { // can exclude
                                            parsedFilters[i].items?[index].currentValue = 2
                                            selectedFilters[filter.id.uuidString] = parsedFilters[i].items?[index]
                                        } else {
                                            parsedFilters[i].items?[index].currentValue = currentValue > 0 ? 0 : 1
                                            if currentValue > 0 {
                                                selectedFilters.removeValue(forKey: filter.id.uuidString)
                                            } else {
                                                selectedFilters[filter.id.uuidString] = parsedFilters[i].items?[index]
                                            }
                                        }
                                    }
                                }
                                convertSelectedToSendable()
                            } label: {
                                HStack {
                                    Text(filter.name)
                                    Spacer()
                                    if filter.type == .sort && filter.currentValue > 0 {
                                        Image(systemName: filter.currentValue > 1 ? "chevron.up" : "chevron.down")
                                    } else if filter.type == .option && filter.currentValue > 0 {
                                        Image(systemName: filter.currentValue > 1 ? "xmark" : "checkmark")
                                    }
                                }
                            }
                            .foregroundColor(.label)
                        }
                    } label: {
                        Text(group.name)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Done")
                }
            }
        }
        .onAppear {
            Task {
                await loadFilters()
                if selected.isEmpty {
                    convertSelectedToSendable()
                } else {
                    convertSentToSelected()
                }
            }
        }
    }
    
    func convertSelectedToSendable() {
        var filters: [Filter] = []
        for (_, parsedFilter) in selectedFilters {
            var newFilter = parsedFilter.filter
            newFilter.value = parsedFilter.currentValue
            filters.append(newFilter)
        }
        selected = filters
    }
    
    func convertSentToSelected() {
        guard !selected.isEmpty else { return }
        selectedFilters = [:]
        for sentFilter in selected {
            var newFilter = parsedFilters.flatMap { $0.items ?? [] }.first { $0.name == sentFilter.name }
            newFilter?.currentValue = sentFilter.value as? Int ?? 0
            selectedFilters[newFilter?.id.uuidString ?? ""] = newFilter
        }
        for (i, _) in parsedFilters.enumerated() {
            for (j, _) in (parsedFilters[i].items ?? []).enumerated() {
                if selectedFilters[parsedFilters[i].items?[j].id.uuidString ?? ""] != nil {
                    parsedFilters[i].items?[j].currentValue = selectedFilters[parsedFilters[i].items?[j].id.uuidString ?? ""]?.currentValue ?? 0
                } else {
                    parsedFilters[i].items?[j].currentValue = 0
                }
            }
        }
    }
    
    func parseFilter(_ filter: Filter) -> ParsedFilter {
        var items: [ParsedFilter]? = nil
        if filter.type == .group {
            items = []
            for subFilter in filter.value as? [Filter] ?? [] {
                items?.append(parseFilter(subFilter))
            }
        }
        var parsedFilter = ParsedFilter(
            type: filter.type,
            name: filter.name,
            filter: filter,
            items: items
        )
        if filter.type == .sort || filter.type == .option {
            parsedFilter.currentValue = parsedFilter.defaultIntValue
            if parsedFilter.defaultIntValue > 0 {
                selectedFilters[parsedFilter.id.uuidString] = parsedFilter
            }
        }
        return parsedFilter
    }
    
    func loadFilters() async {
        filters = (try? await source.getFilters()) ?? []
        parsedFilters = []
        groupsExpanded = []
        
        for filter in filters {
            if filter.type == .group {
                groupsExpanded.append(false)
                parsedFilters.append(parseFilter(filter))
            }
        }
    }
}

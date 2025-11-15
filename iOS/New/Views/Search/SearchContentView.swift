//
//  SearchContentView.swift
//  Aidoku
//
//  Created by Skitty on 11/14/25.
//

import AidokuRunner
import SwiftUI

struct SearchContentView: View {
    @StateObject private var viewModel: ViewModel
    @Binding private var searchText: String
    @Binding var searchCommitToggle: Bool
    @Binding private var filters: [FilterValue]
    let openResult: (ViewModel.SearchResult) -> Void
    let path: NavigationCoordinator

    init(
        viewModel: ViewModel,
        searchText: Binding<String>,
        searchCommitToggle: Binding<Bool> = .constant(false),
        filters: Binding<[FilterValue]>,
        openResult: @escaping (ViewModel.SearchResult) -> Void,
        path: NavigationCoordinator
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self._searchText = searchText
        self._searchCommitToggle = searchCommitToggle
        self._filters = filters
        self.openResult = openResult
        self.path = path
    }

    var body: some View {
        Group {
            if searchText.isEmpty && viewModel.history.isEmpty {
                UnavailableView(
                    NSLocalizedString("NO_RECENT_SEARCHES"),
                    systemImage: "magnifyingglass",
                    description: Text(NSLocalizedString("NO_RECENT_SEARCHES_TEXT"))
                )
                .ignoresSafeArea()
            } else if !searchText.isEmpty && viewModel.resultsIsEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .ignoresSafeArea()
                } else {
                    UnavailableView.search(text: searchText)
                        .ignoresSafeArea()
                }
            } else {
                List {
                    if searchText.isEmpty {
                        if !viewModel.history.isEmpty {
                            historyItems
                        }
                    } else {
                        searchResults
                    }
                }
                .scrollBackgroundHiddenPlease()
                .listStyle(.grouped)
                .environment(\.defaultMinListRowHeight, 10)
            }
        }
        .animation(.default, value: viewModel.results)
        .navigationTitle(NSLocalizedString("SEARCH"))
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                viewModel.results = []
            }
            viewModel.search(query: newValue, delay: true)
        }
        .onChange(of: searchCommitToggle) { _ in
            viewModel.search(query: searchText, delay: false)
        }
        .onChange(of: filters) { newValue in
            viewModel.updateFilters(newValue)
        }
    }

    var historyItems: some View {
        Section {
            ForEach(viewModel.history.reversed(), id: \.self) { item in
                VStack(spacing: 0) {
                    Button {
                        searchText = item
                        viewModel.search(query: item, delay: false)
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                .foregroundStyle(.tint)
                                .imageScale(.small)
                            Text(item)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(ListButtonStyle(tint: false))

                    Divider().padding(.horizontal)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        viewModel.removeHistory(item: item)
                    } label: {
                        Label(NSLocalizedString("DELETE"), systemImage: "trash")
                    }
                }
                .foregroundStyle(.primary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(.zero)
            }
        } header: {
            HStack {
                Text(NSLocalizedString("RECENTLY_SEARCHED"))
                Spacer()
                Button(NSLocalizedString("CLEAR")) {
                    viewModel.clearHistory()
                }
            }
            .font(.body)
            .textCase(nil)
        }
    }

    var searchResults: some View {
        ForEach(viewModel.results) { searchResult in
            let source = searchResult.source
            let result = searchResult.result
            let id = {
                var hasher = Hasher()
                for entry in result.entries {
                    hasher.combine(entry)
                }
                return hasher.finalize()
            }()
            if !result.entries.isEmpty {
                Section {
                    HomeScrollerView(
                        source: source,
                        component: .init(
                            title: nil,
                            value: .scroller(entries: result.entries.map { $0.intoLink() })
                        )
                    )
                    .id("\(source.key).\(id)") // fixes issue with incorrect entries showing
                    .environmentObject(path)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.zero)
                    .listRowSeparator(.hidden)
                } header: {
                    HStack {
                        SourceIconView(
                            sourceId: source.key,
                            imageUrl: source.imageUrl,
                            iconSize: 29
                        )
                        .scaleEffect(0.75)
                        Text(source.name)

                        Spacer()

                        Button(NSLocalizedString("VIEW_MORE")) {
                            openResult(searchResult)
                        }
                    }
                    .font(.body)
                    .textCase(nil)
                }
            }
        }
    }
}

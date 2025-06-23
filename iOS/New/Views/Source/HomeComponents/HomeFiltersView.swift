//
//  HomeFiltersView.swift
//  Aidoku
//
//  Created by Skitty on 1/1/25.
//

import SwiftUI
import AidokuRunner

struct HomeFiltersView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool

    private let filters: [HomeComponent.Value.FilterItem]

    @EnvironmentObject private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source,
        component: HomeComponent,
        partial: Bool = false
    ) {
        self.source = source
        self.component = component
        self.partial = partial

        guard case let .filters(filters) = component.value else {
            fatalError("invalid component type")
        }
        self.filters = filters
    }

    var body: some View {
        VStack(spacing: 6) {
            if let title = component.title {
                TitleView(title: title, subtitle: component.subtitle)
            }

            VStack {
                let items = filters

                let numItems = min(items.count, 5)
                let numRows = (numItems >> 1) + (numItems & 1) // half of numItems, rounded up
                ForEach(0..<numRows, id: \.self) { rowIndex in
                    HStack {
                        ForEach(0..<2) { columnIndex in
                            let index = rowIndex * 2 + columnIndex
                            if index < items.count {
                                if index < numItems || items.count <= 6 {
                                    let item = items[index]
                                    Button {
                                        openFilteredPage(for: item)
                                    } label: {
                                        Text(item.title)
                                            .padding(2)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(BetterBorderedButtonStyle())
                                } else if index == 5 {
                                    Button {
                                        let view = List {
                                            ForEach(items.indices, id: \.self) { offset in
                                                let item = items[offset]
                                                Button {
                                                    openFilteredPage(for: item)
                                                } label: {
                                                    // to style the button like a navlink
                                                    NavigationLink(item.title, destination: EmptyView())
                                                }
                                                .foregroundStyle(.primary)
                                            }
                                        }
                                        let hostingController = UIHostingController(rootView: view)
                                        hostingController.title = component.title
                                        hostingController.navigationItem.largeTitleDisplayMode = .never
                                        path.push(hostingController)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "ellipsis.circle")
                                                .font(.system(size: 15))
                                            Text(NSLocalizedString("SEE_ALL"))
                                        }
                                        .padding(2)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(BetterBorderedButtonStyle())
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    func openFilteredPage(for item: HomeComponent.Value.FilterItem) {
        let view = MangaListView(source: source, title: item.title) { page in
            let filters: [FilterValue] = if let filters = item.values {
                filters
            } else if let filter = source.matchingGenreFilter(for: item.title) {
                [filter]
            } else {
                []
            }
            return try await source.getSearchMangaList(
                query: nil,
                page: page,
                filters: filters
            )
        }.environmentObject(path)

        let hostingController = UIHostingController(rootView: view)
        hostingController.title = item.title
        hostingController.navigationItem.largeTitleDisplayMode = .never
        path.push(hostingController)
    }
}

struct PlaceholderHomeFiltersView: View {
    var showTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showTitle {
                Text("Loading")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .padding(.horizontal)
            }

            Self.mainView
        }
        .redacted(reason: .placeholder)
        .shimmering()
    }

    static var mainView: some View {
        VStack {
            ForEach(0..<3, id: \.self) { _ in
                HStack {
                    ForEach(0..<2) { _ in
                        Button {
                        } label: {
                            Text("Loading")
                                .padding(2)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(BetterBorderedButtonStyle())
                        .disabled(true)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

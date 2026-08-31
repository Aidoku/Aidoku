//
//  HomeLinksView.swift
//  Aidoku
//
//  Created by Skitty on 1/1/25.
//

import AidokuRunner
import SafariServices
import SwiftUI

struct HomeLinksView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool

    private let links: [HomeComponent.Value.Link]

    @EnvironmentObject private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source,
        component: HomeComponent,
        partial: Bool = false
    ) {
        self.source = source
        self.component = component
        self.partial = partial

        guard case let .links(links) = component.value else {
            fatalError("invalid component type")
        }
        self.links = links
    }

    var body: some View {
        VStack(spacing: 2) {
            if let title = component.title {
                TitleView(
                    title: title,
                    subtitle: component.subtitle
                )
            }

            VStack(spacing: 0) {
                ForEach(links.indices, id: \.self) { offset in
                    let link = links[offset]
                    Button {
                        if let value = link.value {
                            switch value {
                                case .url(let urlString):
                                    guard
                                        let url = URL(string: urlString),
                                        url.scheme == "http" || url.scheme == "https"
                                    else { return }
                                    path.present(SFSafariViewController(url: url))
                                case .listing(let listing):
                                    path.push(SourceListingViewController(source: source, listing: listing))
                                case .manga(let manga):
                                    path.push(MangaViewController(source: source, manga: manga, parent: path.rootViewController))
                            }
                        }
                    } label: {
                        Text(link.title)
                    }
                    .buttonStyle(ListButtonStyle())

                    Divider().padding(.horizontal)
                }
            }
        }
    }
}

struct PlaceholderHomeLinksView: View {
    var showTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
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
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                Button {
                } label: {
                    Text("Loading")
                }
                .buttonStyle(ListButtonStyle())
                .disabled(true)

                Divider().padding(.horizontal)
            }
        }
        .padding(.horizontal)
    }
}

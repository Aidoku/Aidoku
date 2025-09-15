//
//  HomeImageScrollerView.swift
//  Aidoku
//
//  Created by Skitty on 5/12/25.
//

import AidokuRunner
import Combine
import SwiftUI
import SafariServices

struct HomeImageScrollerView: View {
    let source: AidokuRunner.Source
    let component: HomeComponent
    let partial: Bool

    private let links: [HomeComponent.Value.Link]
    private let autoScrollInterval: TimeInterval?
    private let width: CGFloat?
    private let height: CGFloat?

    @State private var timer: AnyPublisher<Publishers.Autoconnect<Timer.TimerPublisher>.Output, Publishers.Autoconnect<Timer.TimerPublisher>.Failure>?
    @State private var timerPublish = false
    @State private var timerPaused = false
    @State private var currentPage: Int? = 0

    @EnvironmentObject private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source,
        component: HomeComponent,
        partial: Bool = false
    ) {
        self.source = source
        self.component = component
        self.partial = partial
        guard case let .imageScroller(links, autoScrollInterval, width, height) = component.value else {
            fatalError("invalid component type")
        }
        self.links = links
        self.autoScrollInterval = autoScrollInterval
        self.width = width.flatMap(CGFloat.init)
        self.height = height.flatMap(CGFloat.init)
        if let autoScrollInterval {
            self._timer = State(initialValue: Timer.publish(every: autoScrollInterval, on: .main, in: .common).autoconnect().eraseToAnyPublisher())
        } else {
            self.timer = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            if let title = component.title {
                TitleView(
                    title: title,
                    subtitle: component.subtitle
                )
            }

            if partial && links.isEmpty {
                PlaceholderHomeImageScrollerView.mainView
                    .redacted(reason: .placeholder)
                    .shimmering()
            } else {
                let scrollView = ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(links.indices, id: \.self) { offset in
                            let link = links[offset]
                            let label = VStack(alignment: .leading) {
                                MangaCoverView(
                                    source: source,
                                    coverImage: link.imageUrl ?? "",
                                    width: width,
                                    height: height ?? 140,
                                    placeholder: "BannerPlaceholder"
                                )
                            }
                            if let value = link.value {
                                Button {
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
                                } label: {
                                    label
                                }
                                .foregroundStyle(.primary)
                                .buttonStyle(.borderless)
                            } else {
                                label
                            }
                        }
                    }
                    .padding(.horizontal)
                    .scrollTargetLayoutPlease()
                }
                .scrollViewAlignedPlease()
                .scrollPositionPlease(id: $currentPage, anchor: .leading)

                if let timer {
                    scrollView
                        .onReceive(timer) { _ in
                            guard !timerPaused else { return }
                            let nextPage = ((currentPage ?? 0) + 1) % links.count
                            timerPublish = true
                            withAnimation {
                                currentPage = nextPage
                            }
                        }
                        .onChange(of: currentPage) { _ in
                            if timerPublish {
                                timerPublish = false
                                return
                            }
                            // delay the timer (by restarting it) whenever we scroll manually
                            self.timer = timer.delay(for: 0, scheduler: RunLoop.main).eraseToAnyPublisher()
                        }
                        .onAppear {
                            timerPaused = false
                        }
                        .onDisappear {
                            timerPaused = true
                        }
                } else {
                    scrollView
                }
            }
        }
    }
}

struct PlaceholderHomeImageScrollerView: View {
    var showTitle: Bool = false

    var body: some View {
        VStack(alignment: .leading) {
            if showTitle {
                Text("Loading")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .padding(.horizontal)
            }

            Self.mainView
        }
        .redacted(reason: .placeholder)
        .shimmering()
    }

    static var mainView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(0..<20) { _ in
                    Rectangle()
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 140 * 3/2, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    VStack {
        HomeImageScrollerView(
            source: .demo(),
            component: .init(
                title: "Title",
                value: .imageScroller(
                    links: [.init(title: "", imageUrl: "https://aidoku.app/images/icon.png", value: .url("https://aidoku.app"))],
                    autoScrollInterval: nil
                )
            )
        )
        PlaceholderHomeImageScrollerView()
    }
    .padding()
}

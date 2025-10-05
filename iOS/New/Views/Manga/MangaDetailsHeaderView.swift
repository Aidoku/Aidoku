//
//  MangaDetailsHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import SwiftUI
import AidokuRunner
import MarkdownUI
import NukeUI
import SafariServices

struct MangaDetailsHeaderView: View {
    let source: AidokuRunner.Source?

    @Binding var manga: AidokuRunner.Manga
    @Binding var chapters: [AidokuRunner.Chapter]
    @Binding var nextChapter: AidokuRunner.Chapter?
    @Binding var readingInProgress: Bool
    @Binding var allChaptersLocked: Bool
    @Binding var allChaptersRead: Bool
    @Binding var initialDataLoaded: Bool

    @Binding var bookmarked: Bool
    @Binding var coverPressed: Bool
    @Binding var chapterSortOption: ChapterSortOption
    @Binding var chapterSortAscending: Bool

    @Binding var filters: [ChapterFilterOption]
    @Binding var langFilter: String?
    @Binding var scanlatorFilter: [String]

    @Binding var descriptionExpanded: Bool

    @Binding var chapterTitleDisplayMode: ChapterTitleDisplayMode

    var onTrackerButtonPressed: (() -> Void)?
    var onReadButtonPressed: (() -> Void)?

    @EnvironmentObject private var path: NavigationCoordinator

    @State private var readButtonText = NSLocalizedString("LOADING_ELLIPSIS")
    @State private var readButtonDisabled = true
    @State private var animationTrigger = false
    @State private var longHeldBookmark = false
    @State private var longHeldSafari = false
    @State private var isTracking = false

    static let coverWidth: CGFloat = 114

    init(
        source: AidokuRunner.Source?,
        manga: Binding<AidokuRunner.Manga>,
        chapters: Binding<[AidokuRunner.Chapter]>,
        nextChapter: Binding<AidokuRunner.Chapter?>,
        readingInProgress: Binding<Bool>,
        allChaptersLocked: Binding<Bool>,
        allChaptersRead: Binding<Bool>,
        initialDataLoaded: Binding<Bool>,
        bookmarked: Binding<Bool>,
        coverPressed: Binding<Bool>,
        chapterSortOption: Binding<ChapterSortOption>,
        chapterSortAscending: Binding<Bool>,
        filters: Binding<[ChapterFilterOption]>,
        langFilter: Binding<String?>,
        scanlatorFilter: Binding<[String]>,
        descriptionExpanded: Binding<Bool>,
        chapterTitleDisplayMode: Binding<ChapterTitleDisplayMode>,
        onTrackerButtonPressed: (() -> Void)? = nil,
        onReadButtonPressed: (() -> Void)? = nil
    ) {
        self.source = source
        self._manga = manga
        self._chapters = chapters
        self._nextChapter = nextChapter
        self._readingInProgress = readingInProgress
        self._allChaptersLocked = allChaptersLocked
        self._allChaptersRead = allChaptersRead
        self._initialDataLoaded = initialDataLoaded
        self._bookmarked = bookmarked
        self._coverPressed = coverPressed
        self._chapterSortOption = chapterSortOption
        self._chapterSortAscending = chapterSortAscending
        self._filters = filters
        self._langFilter = langFilter
        self._scanlatorFilter = scanlatorFilter
        self._descriptionExpanded = descriptionExpanded
        self._chapterTitleDisplayMode = chapterTitleDisplayMode
        self.onTrackerButtonPressed = onTrackerButtonPressed
        self.onReadButtonPressed = onReadButtonPressed

        self._isTracking = State(initialValue: TrackerManager.shared.isTracking(
            sourceId: manga.wrappedValue.sourceKey,
            mangaId: manga.wrappedValue.key
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    Button {
                        coverPressed = true
                    } label: {
                        // 2:3 aspect ratio
                        MangaCoverView(
                            source: source,
                            coverImage: manga.cover ?? "",
                            width: Self.coverWidth,
                            height: Self.coverWidth * 3/2
                        )
                        .id(manga.cover ?? "")
                    }
                    .buttonStyle(DarkOverlayButtonStyle())
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)

                    Text(manga.title)
                        .lineLimit(4)
                        .font(.system(.title2).weight(.semibold))
                        .textSelection(.enabled)
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.75)
                        .contentTransitionDisabledPlease()
                        .padding(.bottom, 4)

                    if let authors = manga.authors, !authors.isEmpty {
                        let label = Text(authors.joined(separator: ", "))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.bottom, 6)
                            .textSelection(.enabled)
                            .transition(.opacity)

                        if let source, source.supportsAuthorSearch {
                            Button {
                                // we'll need a better ui in the future for different author selection
                                guard let author = authors.first else { return }
                                let view = MangaListView(source: source, title: author) { page in
                                    try await source.getSearchMangaList(query: nil, page: page, filters: [
                                        .text(id: "author", value: author)
                                    ])
                                }.environmentObject(path)
                                path.push(view, title: author)
                            } label: {
                                label
                            }
                            .buttonStyle(.borderless)
                        } else {
                            label
                        }
                    }

                    labelsView

                    buttonsView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 174)
            .padding(.bottom, 14)
            .padding(.horizontal, 20)

            if let description = manga.description, !description.isEmpty {
                ExpandableTextView(text: description, expanded: $descriptionExpanded)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 20)
                    .foregroundStyle(.secondary)
            }

            tagsView

            // read button
            Button {
                onReadButtonPressed?()
            } label: {
                Text(readButtonText)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .padding(11)
            .foregroundStyle(.white)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.bottom, 10)
            .padding(.horizontal, 20)
            .allowsHitTesting(!readButtonDisabled)

            ChapterListHeaderView(
                allChapters: manga.chapters,
                filteredChapters: manga.chapters != nil ? chapters : (initialDataLoaded ? [] : nil),
                sortOption: $chapterSortOption,
                sortAscending: $chapterSortAscending,
                filters: $filters,
                langFilter: $langFilter,
                scanlatorFilter: $scanlatorFilter,
                displayMode: $chapterTitleDisplayMode,
                mangaUniqueKey: manga.uniqueKey
            )
            .padding(.horizontal, 20)

            // separator
            if !chapters.isEmpty {
                Divider()
            }
        }
        .animation(.default, value: animationTrigger)
        .animation(.default, value: descriptionExpanded)
        .foregroundStyle(.primary)
        .textCase(.none)
        .padding(.top, 10)
        .onChange(of: manga) { _ in
            animationTrigger.toggle()
        }
        .onChange(of: nextChapter) { _ in
            updateReadButtonText()
        }
        .onChange(of: readingInProgress) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersLocked) { _ in
            updateReadButtonText()
        }
        .onChange(of: allChaptersRead) { _ in
            updateReadButtonText()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateTrackers)) { _ in
            isTracking = TrackerManager.shared.isTracking(
                sourceId: manga.sourceKey,
                mangaId: manga.key
            )
        }
        .onAppear {
            updateReadButtonText()
        }
    }

    @ViewBuilder
    var labelsView: some View {
        if manga.status != .unknown || (manga.contentRating != .unknown && manga.contentRating != .safe) {
            HStack(spacing: 6) {
                if manga.status != .unknown {
                    LabelView(text: manga.status.title)
                }
                if manga.contentRating != .unknown && manga.contentRating != .safe {
                    LabelView(
                        text: manga.contentRating.title,
                        background: manga.contentRating == .suggestive
                            ? .orange.opacity(0.3)
                            : .red.opacity(0.3)
                    )
                }
                if let source, bookmarked {
                    LabelView(
                        text: source.name,
                        background: Color(red: 0.25, green: 0.55, blue: 1).opacity(0.3)
                    )
                }
            }
            .padding(.bottom, 8)
            .animation(.default, value: manga.status)
            .animation(.default, value: bookmarked)
        }
    }

    var buttonsView: some View {
        HStack(spacing: 8) {
            Button {
                // long holding also triggers a press on release, so cancel that
                if longHeldBookmark {
                    longHeldBookmark = false
                    return
                }
                Task {
                    await toggleBookmarked()
                }
            } label: {
                Image(systemName: "bookmark.fill")
            }
            .buttonStyle(MangaActionButtonStyle(selected: bookmarked))
            .simultaneousGesture(
                // on long hold, show category select
                LongPressGesture()
                    .onEnded { _ in
                        if
                            bookmarked,
                            !CoreDataManager.shared.getCategories(sorted: false).isEmpty
                        {
                            longHeldBookmark = true
                            path.present(
                                UINavigationController(
                                    rootViewController: CategorySelectViewController(
                                        manga: manga
                                    )
                                )
                            )
                        }
                    }
            )

            if TrackerManager.shared.hasAvailableTrackers(sourceKey: manga.sourceKey, mangaKey: manga.key) {
                Button {
                    onTrackerButtonPressed?()
                } label: {
                    Image(systemName: "clock.arrow.2.circlepath")
                }
                .buttonStyle(MangaActionButtonStyle(selected: isTracking))
            }

            if let url = manga.url {
                Button {
                    guard url.scheme == "http" || url.scheme == "https" else { return }
                    path.present(SFSafariViewController(url: url))
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(MangaActionButtonStyle())
                .transition(.opacity)
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { finished in
                            if finished {
                                UIPasteboard.general.string = url.absoluteString
                                longHeldSafari = true
                            }
                        }
                )
                .alert(
                    NSLocalizedString("LINK_COPIED"),
                    isPresented: $longHeldSafari
                ) {
                    Button(NSLocalizedString("OK"), role: .cancel) {}
                } message: {
                    Text(NSLocalizedString("LINK_COPIED_TEXT"))
                }
            }
        }
    }

    @ViewBuilder
    var tagsView: some View {
        if let tags = manga.tags, !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(manga.tags ?? [], id: \.self) { tag in
                        let label = TagView(text: tag)
                        if let source, let filter = source.matchingGenreFilter(for: tag) {
                            Button {
                                let view = MangaListView(source: source, title: tag) { page in
                                    try await source.getSearchMangaList(query: nil, page: page, filters: [
                                        filter
                                    ])
                                }.environmentObject(path)
                                path.push(view, title: tag)
                            } label: {
                                label
                            }
                        } else {
                            label
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
    }

    func toggleBookmarked() async {
        let sourceId = manga.sourceKey
        let mangaId = manga.key
        let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
            CoreDataManager.shared.hasLibraryManga(
                sourceId: sourceId,
                mangaId: mangaId,
                context: context
            )
        }
        if inLibrary {
            // remove from library
            await MangaManager.shared.removeFromLibrary(
                sourceId: sourceId,
                mangaId: mangaId
            )
            bookmarked = false
        } else {
            // check if category select should open
            let categories = CoreDataManager.shared.getCategoryTitles()
            var shouldAskCategory = !categories.isEmpty
            if
                let defaultCategory = UserDefaults.standard.string(forKey: "Library.defaultCategory"),
                defaultCategory == "none" || categories.contains(defaultCategory)
            {
                shouldAskCategory = false
            }
            if shouldAskCategory { // open category select view
                path.present(
                    UINavigationController(rootViewController: CategorySelectViewController(
                        manga: manga
                    ))
                )
            } else { // add to library
                bookmarked = true
                await MangaManager.shared.addToLibrary(
                    sourceId: sourceId,
                    manga: manga,
                    chapters: manga.chapters ?? []
                )
            }
        }
    }

    func updateReadButtonText() {
        var title = ""
        if allChaptersLocked {
            title = NSLocalizedString("ALL_CHAPTERS_LOCKED", comment: "")
            readButtonDisabled = true
        } else if allChaptersRead {
            title = NSLocalizedString("ALL_CHAPTERS_READ", comment: "")
            readButtonDisabled = true
        } else if source == nil {
            title = NSLocalizedString("UNAVAILABLE", comment: "")
            readButtonDisabled = true
        } else {
            if let chapter = nextChapter {
                if !readingInProgress {
                    title = NSLocalizedString("START_READING", comment: "")
                } else {
                    title = NSLocalizedString("CONTINUE_READING", comment: "")
                }
                switch chapterTitleDisplayMode {
                    case .volume:
                        if let volumeNum = chapter.volumeNumber {
                            title += " " + String(format: NSLocalizedString("VOL_X"), volumeNum)
                        } else if let chapterNum = chapter.chapterNumber {
                            // Force display as volume if no volume number
                            title += " " + String(format: NSLocalizedString("VOL_X"), chapterNum)
                        }
                    case .chapter:
                        if let chapterNum = chapter.chapterNumber {
                            title += " " + String(format: NSLocalizedString("CH_X"), chapterNum)
                        } else if let volumeNum = chapter.volumeNumber {
                            // Force display as chapter if no chapter number
                            title += " " + String(format: NSLocalizedString("CH_X"), volumeNum)
                        }
                    case .default:
                        if let volumeNum = chapter.volumeNumber {
                            title += " " + String(format: NSLocalizedString("VOL_X"), volumeNum)
                        }
                        if let chapterNum = chapter.chapterNumber {
                            title += " " + String(format: NSLocalizedString("CH_X"), chapterNum)
                        }
                }
            } else {
                title = NSLocalizedString("NO_CHAPTERS_AVAILABLE", comment: "")
            }
            readButtonDisabled = false
        }
        readButtonText = title
    }
}

struct LabelView: View {
    let text: String
    var background = Color(UIColor.tertiarySystemFill)

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .font(.caption2)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .textSelection(.enabled)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 100))
    }
}

private struct MangaActionButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
//        Group {
//            if selected {
//                configuration.label
//                    .foregroundStyle(.white)
//            } else {
//                configuration.label
//                    .foregroundStyle(.tint)
//            }
//        }
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .opacity(configuration.isPressed ? 0.4 : 1)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 40, height: 32)
            .background(selected ? Color.accentColor : Color(UIColor.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    @Previewable @State var bookmarked = false
    @Previewable @State var chapterSortOption = ChapterSortOption.sourceOrder
    @Previewable @State var chapterSortAscending = false

    @Previewable @State var filters: [ChapterFilterOption] = []
    @Previewable @State var langFilter: String?
    @Previewable @State var scanlatorFilter: [String] = []
    @Previewable @State var chapterTitleDisplayMode = ChapterTitleDisplayMode.default

    MangaDetailsHeaderView(
        source: AidokuRunner.Source.demo(),
        manga: Binding.constant(AidokuRunner.Manga(
            sourceKey: "",
            key: "",
            title: "Manga",
            authors: ["Author"],
            description: "Description"
        )),
        chapters: Binding.constant([]),
        nextChapter: Binding.constant(nil),
        readingInProgress: Binding.constant(false),
        allChaptersLocked: Binding.constant(false),
        allChaptersRead: Binding.constant(false),
        initialDataLoaded: Binding.constant(true),
        bookmarked: $bookmarked,
        coverPressed: Binding.constant(false),
        chapterSortOption: $chapterSortOption,
        chapterSortAscending: $chapterSortAscending,
        filters: $filters,
        langFilter: $langFilter,
        scanlatorFilter: $scanlatorFilter,
        descriptionExpanded: Binding.constant(false),
        chapterTitleDisplayMode: $chapterTitleDisplayMode,
    )
}

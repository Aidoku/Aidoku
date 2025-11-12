//
//  MangaView.swift
//  Aidoku
//
//  Created by Skitty on 8/14/23.
//

import AidokuRunner
import NukeUI
import SwiftUI

struct MangaView: View {
    @StateObject private var viewModel: ViewModel

    @State private var scrollToChapterKey: String?

    @State private var editMode = EditMode.inactive
    @State private var selectedChapters = Set<String>()

    @State private var showingCoverView = false
    @State private var showRemoveAllConfirm = false
    @State private var showRemoveSelectedConfirm = false
    @State private var showConnectionAlert = false

    @State private var detailsLoaded = false
    @State private var descriptionExpanded = false

    @State private var loadingAlert: UIAlertController?

    private var path: NavigationCoordinator

    init(
        source: AidokuRunner.Source? = nil,
        manga: AidokuRunner.Manga,
        path: NavigationCoordinator,
        scrollToChapterKey: String? = nil
    ) {
        let source = source ?? SourceManager.shared.source(for: manga.sourceKey)
        self._viewModel = StateObject(wrappedValue: ViewModel(source: source, manga: manga))
        self.path = path
        self._scrollToChapterKey = State(initialValue: scrollToChapterKey)
    }

    var body: some View {
        let list = ScrollViewReader { proxy in
            List(selection: $selectedChapters) {
                headerView

                if let error = viewModel.error {
                    ErrorView(error: error) {
                        viewModel.error = nil
                        await viewModel.fetchData()
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.chapters.indices, id: \.self) { index in
                        let chapter = viewModel.chapters[index]
                        viewForChapter(chapter, index: index)
                    }

                    // hide the separator if there are no chapters, or all the chapters are filtered and the other section is shown
                    if !viewModel.chapters.isEmpty || (!(viewModel.manga.chapters?.isEmpty ?? true) && !viewModel.otherDownloadedChapters.isEmpty) {
                        bottomSeparator
                    }
                }

                if !viewModel.otherDownloadedChapters.isEmpty {
                    VStack {
                        HStack {
                            Text(NSLocalizedString("DOWNLOADED_CHAPTERS"))
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        ListDivider()
                    }
                    .listRowInsets(.zero)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    ForEach(viewModel.otherDownloadedChapters.indices, id: \.self) { index in
                        let chapter = viewModel.otherDownloadedChapters[index]
                        viewForChapter(chapter, index: index, secondSection: true)
                    }

                    bottomSeparator
                }
            }
            // decrease the min row height for the bottom separator/spacing
            .environment(\.defaultMinListRowHeight, 10)
            .transition(.opacity)
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialogOrAlert(
                NSLocalizedString("REMOVE_ALL_DOWNLOADS"),
                isPresented: $showRemoveAllConfirm,
                actions: {
                    Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                    Button(NSLocalizedString("REMOVE"), role: .destructive) {
                        Task {
                            await DownloadManager.shared.deleteChapters(for: viewModel.manga.identifier)
                        }
                    }
                },
                message: {
                    Text(NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM"))
                }
            )
            .confirmationDialogOrAlert(
                NSLocalizedString("REMOVE_DOWNLOADS"),
                isPresented: $showRemoveSelectedConfirm,
                actions: {
                    Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                    Button(NSLocalizedString("REMOVE"), role: .destructive) {
                        Task {
                            await DownloadManager.shared.delete(chapters: selectedChapters.map {
                                .init(
                                    sourceKey: viewModel.manga.sourceKey,
                                    mangaKey: viewModel.manga.key,
                                    chapterKey: $0
                                )
                            })
                            withAnimation {
                                editMode = .inactive
                            }
                        }
                    }
                },
                message: {
                    Text(NSLocalizedString("REMOVE_DOWNLOADS_CONFIRM"))
                }
            )
            .alert(
                NSLocalizedString("NO_WIFI_ALERT_TITLE"),
                isPresented: $showConnectionAlert,
                actions: {
                    Button(NSLocalizedString("OK"), role: .cancel) {}
                },
                message: {
                    Text(NSLocalizedString("NO_WIFI_ALERT_MESSAGE"))
                }
            )
            .scrollBackgroundHiddenPlease()
            .navigationBarBackButtonHidden(editMode == .active)
            .fullScreenCover(isPresented: $showingCoverView) {
                MangaCoverPageView(
                    source: viewModel.source,
                    manga: viewModel.manga
                )
            }
            .task {
                guard !detailsLoaded else { return }
                await viewModel.markOpened()
                await viewModel.fetchDetails()
                if let scrollToChapterKey {
                    withAnimation {
                        proxy.scrollTo(scrollToChapterKey, anchor: .center)
                    }
                    self.scrollToChapterKey = nil
                }
                await viewModel.syncTrackerProgress()
                detailsLoaded = true
            }
            .onChange(of: editMode) { mode in
                guard let navigationController = path.rootViewController?.navigationController
                else { return }
                if mode == .active {
                    UIView.animate(withDuration: 0.3) {
                        navigationController.isToolbarHidden = false
                        navigationController.toolbar.alpha = 1
                        if #available(iOS 26.0, *) {
                            navigationController.tabBarController?.isTabBarHidden = true
                        }
                    }
                } else {
                    UIView.animate(withDuration: 0.3) {
                        navigationController.toolbar.alpha = 0
                        if #available(iOS 26.0, *) {
                            navigationController.tabBarController?.isTabBarHidden = false
                        }
                    } completion: { _ in
                        navigationController.isToolbarHidden = true
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    toolbarContentBase

                    ToolbarItemGroup(placement: .bottomBar) {
                        if editMode == .active {
                            toolbar
                        }
                    }
                }
        }
    }
}

extension MangaView {
    var headerView: some View {
        ZStack {
            MangaDetailsHeaderView(
                source: viewModel.source,
                manga: $viewModel.manga,
                chapters: $viewModel.chapters,
                nextChapter: $viewModel.nextChapter,
                readingInProgress: $viewModel.readingInProgress,
                allChaptersLocked: $viewModel.allChaptersLocked,
                allChaptersRead: $viewModel.allChaptersRead,
                initialDataLoaded: $viewModel.initialDataLoaded,
                bookmarked: $viewModel.bookmarked,
                coverPressed: $showingCoverView,
                chapterSortOption: $viewModel.chapterSortOption,
                chapterSortAscending: $viewModel.chapterSortAscending,
                filters: $viewModel.chapterFilters,
                langFilter: $viewModel.chapterLangFilter,
                scanlatorFilter: $viewModel.chapterScanlatorFilter,
                descriptionExpanded: $descriptionExpanded,
                chapterTitleDisplayMode: $viewModel.chapterTitleDisplayMode,
                hasOtherDownloads: !viewModel.otherDownloadedChapters.isEmpty,
                onTrackerButtonPressed: {
                    let vc = TrackerModalViewController(manga: viewModel.manga)
                    vc.modalPresentationStyle = .overFullScreen
                    path.present(vc, animated: false)
                },
                onReadButtonPressed: {
                    if let nextChapter = viewModel.nextChapter {
                        openReaderView(chapter: nextChapter)
                    }
                }
            )
            .environmentObject(path)
            .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .listRowInsets(.zero)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    var bottomSeparator: some View {
        VStack {
            ListDivider() // final, full width separator
            Color.clear.frame(height: 28) // padding for bottom of list
        }
        .padding(.top, {
            // add a little spacing above on ios 15, since the separator ends up hidden
            if #available(iOS 16.0, *) { 0 } else { 0.5 }
        }())
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
    }

    @ViewBuilder
    func viewForChapter(_ chapter: AidokuRunner.Chapter, index: Int, secondSection: Bool = false) -> some View {
        let last = index == (secondSection ? viewModel.otherDownloadedChapters : viewModel.chapters).count - 1
        let downloadStatus = viewModel.downloadStatus[chapter.key, default: .none]
        let downloaded = downloadStatus == .finished
        let locked = chapter.locked && !downloaded
        let opacity: Double = if #available(iOS 17.0, *), locked {
            0.5
        } else {
            1
        }

        ChapterCellView(
            source: viewModel.source,
            sourceKey: viewModel.manga.sourceKey,
            chapter: chapter,
            read: viewModel.readingHistory[chapter.key]?.page == -1,
            page: viewModel.readingHistory[chapter.key]?.page,
            downloadStatus: downloadStatus,
            downloadProgress: viewModel.downloadProgress[chapter.key],
            displayMode: viewModel.chapterTitleDisplayMode,
            isEditing: editMode == .active
        ) {
            if editMode == .inactive {
                openReaderView(chapter: chapter)
            } else {
                if selectedChapters.contains(chapter.key) {
                    selectedChapters.remove(chapter.key)
                } else {
                    selectedChapters.insert(chapter.key)
                }
            }
        } contextMenu: {
            contextMenu(
                chapter: chapter,
                downloadStatus: downloadStatus,
                index: index,
                last: last,
                secondSection: secondSection
            )
        }
        // use equatableview to determine when to refresh the view
        // improves the scrolling performance of the list
        .equatable()
        .listRowInsets(.zero)
        .disabled(locked)
        .opacity(opacity)
        .id(chapter.key)
        .tag(chapter.key, selectable: !locked)
    }

    @ViewBuilder
    func contextMenu(
        chapter: AidokuRunner.Chapter,
        downloadStatus: DownloadStatus,
        index: Int,
        last: Bool,
        secondSection: Bool
    ) -> some View {
        Section {
            if viewModel.manga.isLocal() {
                // if the chapter is from the local source, add a button to remove it instead of download
                Button(role: .destructive) {
                    Task {
                        await LocalFileManager.shared.removeChapter(
                            mangaId: viewModel.manga.key,
                            chapterId: chapter.key
                        )
                        if let index = viewModel.chapters.firstIndex(of: chapter) {
                            withAnimation {
                                _ = viewModel.chapters.remove(at: index)
                            }
                        }
                    }
                } label: {
                    Label(NSLocalizedString("REMOVE"), systemImage: "trash")
                }
            } else {
                let identifier = ChapterIdentifier(
                    sourceKey: viewModel.manga.sourceKey,
                    mangaKey: viewModel.manga.key,
                    chapterKey: chapter.key
                )
                if downloadStatus == .finished {
                    Button(role: .destructive) {
                        Task {
                            await DownloadManager.shared.delete(chapters: [identifier])
                        }
                    } label: {
                        Label(NSLocalizedString("REMOVE_DOWNLOAD"), systemImage: "trash")
                    }
                } else if downloadStatus == .downloading {
                    Button(role: .destructive) {
                        Task {
                            await DownloadManager.shared.cancelDownload(for: identifier)
                        }
                    } label: {
                        Label(NSLocalizedString("CANCEL_DOWNLOAD"), systemImage: "xmark")
                    }
                } else if viewModel.source != nil {
                    Button {
                        let downloadOnlyOnWifi = UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi")
                        if
                            downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi
                                || !downloadOnlyOnWifi
                        {
                            Task {
                                await DownloadManager.shared.download(
                                    manga: viewModel.manga,
                                    chapters: [chapter]
                                )
                            }
                        } else {
                            showConnectionAlert = true
                        }
                    } label: {
                        Label(NSLocalizedString("DOWNLOAD"), systemImage: "arrow.down.circle")
                    }
                }
            }
        }
        Divider()
        Section {
            if viewModel.readingHistory[chapter.key]?.page != nil {
                Button {
                    Task {
                        await viewModel.markUnread(chapters: [chapter])
                    }
                } label: {
                    Label(NSLocalizedString("MARK_UNREAD"), systemImage: "eye.slash")
                }
            }
            if viewModel.readingHistory[chapter.key]?.page != -1 {
                Button {
                    Task {
                        await viewModel.markRead(chapters: [chapter])
                    }
                } label: {
                    Label(NSLocalizedString("MARK_READ"), systemImage: "eye")
                }
            }
            if !last && !secondSection {
                Menu(NSLocalizedString("MARK_PREVIOUS")) {
                    Button {
                        let chapters = [AidokuRunner.Chapter](viewModel.chapters[
                            index + 1..<viewModel.chapters.count
                        ])
                        Task {
                            await viewModel.markRead(chapters: chapters)
                        }
                    } label: {
                        Label(NSLocalizedString("READ"), systemImage: "eye")
                    }
                    Button {
                        let chapters = [AidokuRunner.Chapter](viewModel.chapters[
                            index + 1..<viewModel.chapters.count
                        ])
                        Task {
                            await viewModel.markUnread(chapters: chapters)
                        }
                    } label: {
                        Label(NSLocalizedString("UNREAD"), systemImage: "eye.slash")
                    }
                }
            }
        }
        if let url = chapter.url {
            Divider()
            Section {
                Button {
                    showShareSheet(url: url)
                } label: {
                    Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    @ViewBuilder
    var rightNavbarButton: some View {
        RightNavbarButton(
            viewModel: viewModel,
            markAllRead: {
                // only show loading indicator for a larger number of chapters
                if viewModel.chapters.count > 100 {
                    showLoadingIndicator()
                }
                Task {
                    await viewModel.markRead(chapters: viewModel.chapters)
                    hideLoadingIndicator()
                }
            },
            markAllUnread: {
                if viewModel.chapters.count > 100 {
                    showLoadingIndicator()
                }
                Task {
                    await viewModel.markUnread(chapters: viewModel.chapters)
                    hideLoadingIndicator()
                }
            },
            editCategories: {
                path.present(
                    UINavigationController(
                        rootViewController: CategorySelectViewController(
                            manga: viewModel.manga
                        )
                    )
                )
            },
            migrate: {
                let migrateView = MigrateMangaView(manga: [viewModel.manga.toOld()])
                path.present(UIHostingController(
                    rootView: SwiftUINavigationView(rootView: migrateView)
                ))
            },
            showShareSheet: showShareSheet(url:),
            removeDownloads: {
                showRemoveAllConfirm = true
            },
            editMode: $editMode
        ).equatable()
    }
}

extension MangaView {
    @ToolbarContentBuilder
    var toolbarContentBase: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            rightNavbarButton
        }

        ToolbarItem(placement: .topBarLeading) {
            if editMode == .active {
                let allSelected = selectedChapters.count == viewModel.chapters.count
                Button {
                    if allSelected {
                        selectedChapters = Set()
                    } else {
                        selectedChapters = Set(viewModel.chapters.map { $0.key })
                    }
                } label: {
                    if allSelected {
                        Text(NSLocalizedString("DESELECT_ALL"))
                    } else {
                        Text(NSLocalizedString("SELECT_ALL"))
                    }
                }
                .disabled(viewModel.chapters.isEmpty)
            }
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        toolbarContentBase

        if editMode == .active {
            ToolbarItem(placement: .bottomBar) {
                toolbarMarkMenu
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)

            if !viewModel.manga.isLocal() {
                ToolbarItem(placement: .bottomBar) {
                    toolbarDownloadButton
                }
            }
        }
    }

    var toolbar: some View {
        HStack {
            toolbarMarkMenu

            Spacer()

            toolbarDownloadButton
        }
    }

    var toolbarMarkMenu: some View {
        Menu(NSLocalizedString("MARK")) {
            let title = if selectedChapters.count == 1 {
                NSLocalizedString("1_CHAPTER")
            } else {
                String(format: NSLocalizedString("%i_CHAPTERS"), selectedChapters.count)
            }
            Section(title) {
                Button {
                    let markChapters = selectedChapters.compactMap { id in
                        viewModel.chapters.first(where: { $0.key == id })
                    }
                    Task {
                        await viewModel.markUnread(chapters: markChapters)
                    }
                    withAnimation {
                        editMode = .inactive
                    }
                } label: {
                    Label(NSLocalizedString("UNREAD"), systemImage: "eye.slash")
                }
                Button {
                    let markChapters = selectedChapters.compactMap { id in
                        viewModel.chapters.first(where: { $0.key == id })
                    }
                    Task {
                        await viewModel.markRead(chapters: markChapters)
                    }
                    withAnimation {
                        editMode = .inactive
                    }
                } label: {
                    Label(NSLocalizedString("READ"), systemImage: "eye")
                }
            }
        }
        .disabled(selectedChapters.isEmpty)
    }

    @ViewBuilder
    var toolbarDownloadButton: some View {
        let allChaptersQueued = !selectedChapters.contains(where: {
            viewModel.downloadStatus[$0] != .queued
        })
        let allChaptersDownloaded = !selectedChapters.contains(where: {
            viewModel.downloadStatus[$0] != .finished
        })
        if !selectedChapters.isEmpty && allChaptersQueued {
            Button(NSLocalizedString("CANCEL")) {
                Task {
                    await DownloadManager.shared.cancelDownloads(for: selectedChapters.map {
                        .init(
                            sourceKey: viewModel.manga.sourceKey,
                            mangaKey: viewModel.manga.key,
                            chapterKey: $0
                        )
                    })
                }
                withAnimation {
                    editMode = .inactive
                }
            }
        } else if !selectedChapters.isEmpty && allChaptersDownloaded {
            Button(NSLocalizedString("REMOVE")) {
                showRemoveSelectedConfirm = true
            }
        } else {
            Button(NSLocalizedString("DOWNLOAD")) {
                let downloadChapters = (viewModel.manga.chapters ?? viewModel.chapters)
                    .filter { chapter in
                        let isSelected = selectedChapters.contains(chapter.key)
                        guard isSelected else { return false }
                        let isDownloaded = viewModel.downloadStatus[chapter.key] == .finished
                        let isDownloading = viewModel.downloadStatus[chapter.key] == .downloading
                        let isQueued = viewModel.downloadStatus[chapter.key] == .queued
                        guard !isDownloaded, !isDownloading, !isQueued else { return false }
                        return true
                    }
                    .reversed()

                let downloadOnlyOnWifi = UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi")
                if
                    downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi
                        || !downloadOnlyOnWifi
                {
                    Task {
                        await DownloadManager.shared.download(
                            manga: viewModel.manga,
                            chapters: Array(downloadChapters)
                        )
                    }
                } else {
                    showConnectionAlert = true
                }
                withAnimation {
                    editMode = .inactive
                }
            }
            .disabled(viewModel.source == nil || viewModel.manga.isLocal() || selectedChapters.isEmpty)
        }
    }
}

extension MangaView {
    func openReaderView(chapter: AidokuRunner.Chapter) {
        var mangaWithFilteredChapters = viewModel.manga
        mangaWithFilteredChapters.chapters = viewModel.chapters
        let readerController = ReaderViewController(
            source: viewModel.source,
            manga: mangaWithFilteredChapters,
            chapter: chapter
        )
        let navigationController = ReaderNavigationController(rootViewController: readerController)
        navigationController.modalPresentationStyle = .fullScreen
        path.present(navigationController)
    }

    func showShareSheet(url: URL) {
        let activityViewController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        guard let sourceView = path.rootViewController?.view else { return }
        activityViewController.popoverPresentationController?.sourceView = sourceView
        // manually positioned in top right of screen, near the right navigation bar button
        activityViewController.popoverPresentationController?.sourceRect = CGRect(
            x: UIScreen.main.bounds.width - 30,
            y: 60,
            width: 0,
            height: 0
        )
        path.present(activityViewController)
    }

    func showLoadingIndicator() {
        guard loadingAlert == nil else { return }
        loadingAlert = UIAlertController(
            title: nil,
            message: NSLocalizedString("LOADING_ELLIPSIS", comment: ""),
            preferredStyle: .alert
        )
        guard let loadingAlert else { return }
        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.style = .medium
        loadingIndicator.tag = 3
        loadingIndicator.startAnimating()
        loadingAlert.view.addSubview(loadingIndicator)
        path.present(loadingAlert)
    }

    func hideLoadingIndicator() {
        guard let loadingAlert else { return }
        loadingAlert.dismiss(animated: true)
        self.loadingAlert = nil
    }
}

private struct ChapterCellView<T: View>: View, Equatable {
    let source: AidokuRunner.Source?
    let sourceKey: String
    let chapter: AidokuRunner.Chapter
    let read: Bool
    let page: Int?
    let downloadStatus: DownloadStatus
    let downloadProgress: Float?
    let displayMode: ChapterTitleDisplayMode
    let isEditing: Bool

    var onPressed: (() -> Void)?
    var contextMenu: (() -> T)?

    private var locked: Bool {
        chapter.locked && !(downloadStatus == .finished)
    }

    var body: some View {
        let view = HStack {
            ChapterTableCell(
                source: source,
                sourceKey: sourceKey,
                chapter: chapter,
                read: read,
                page: page,
                downloadStatus: downloadStatus,
                downloadProgress: downloadProgress,
                displayMode: displayMode
            )
        }
        if isEditing {
            view
        } else {
            Button {
                onPressed?()
            } label: {
                view
            }
            .tint(.primary)
            .contextMenu {
                if !locked {
                    contextMenu?()
                }
            }
        }
    }

    static nonisolated func == (lhs: ChapterCellView<T>, rhs: ChapterCellView<T>) -> Bool {
        lhs.chapter == rhs.chapter
            && lhs.read == rhs.read
            && lhs.page == rhs.page
            && lhs.downloadStatus == rhs.downloadStatus
            && lhs.downloadProgress == rhs.downloadProgress
            && lhs.displayMode == rhs.displayMode
            && lhs.isEditing == rhs.isEditing
    }
}

private struct RightNavbarButton: View, Equatable {
    let bookmarked: Bool
    let hasCategories: Bool
    let url: URL?
    let hasDownloads: Bool
    let isEditing: Bool

    let markAllRead: () -> Void
    let markAllUnread: () -> Void
    let editCategories: () -> Void
    let migrate: () -> Void
    let showShareSheet: (URL) -> Void
    let removeDownloads: () -> Void

    @Binding var editMode: EditMode

    init(
        viewModel: MangaView.ViewModel,
        markAllRead: @escaping () -> Void,
        markAllUnread: @escaping () -> Void,
        editCategories: @escaping () -> Void,
        migrate: @escaping () -> Void,
        showShareSheet: @escaping (URL) -> Void,
        removeDownloads: @escaping () -> Void,
        editMode: Binding<EditMode>
    ) {
        self.bookmarked = viewModel.bookmarked
        self.hasCategories = !CoreDataManager.shared.getCategories(sorted: false).isEmpty
        self.url = viewModel.manga.url
        self.hasDownloads = viewModel.downloadStatus.contains(where: { $0.value == .finished })
        self.markAllRead = markAllRead
        self.markAllUnread = markAllUnread
        self.editCategories = editCategories
        self.migrate = migrate
        self.showShareSheet = showShareSheet
        self.removeDownloads = removeDownloads
        self.isEditing = editMode.wrappedValue == .active
        self._editMode = editMode
    }

    var body: some View {
        if editMode == .inactive {
            Menu {
                Menu(NSLocalizedString("MARK_ALL")) {
                    Button {
                        markAllRead()
                    } label: {
                        Label(NSLocalizedString("READ"), systemImage: "eye")
                    }
                    Button {
                        markAllUnread()
                    } label: {
                        Label(NSLocalizedString("UNREAD"), systemImage: "eye.slash")
                    }
                }
                Button {
                    withAnimation {
                        editMode = .active
                    }
                } label: {
                    Label(NSLocalizedString("SELECT_CHAPTERS"), systemImage: "checkmark.circle")
                }
                if bookmarked {
                    if hasCategories {
                        Button {
                            editCategories()
                        } label: {
                            Label(NSLocalizedString("EDIT_CATEGORIES"), systemImage: "folder.badge.gearshape")
                        }
                    }
                    Button {
                        migrate()
                    } label: {
                        Label(NSLocalizedString("MIGRATE"), systemImage: "arrow.left.arrow.right")
                    }
                }
                if let url {
                    Button {
                        showShareSheet(url)
                    } label: {
                        Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                    }
                }

                if hasDownloads {
                    Divider()
                    Button(role: .destructive) {
                        removeDownloads()
                    } label: {
                        Label(
                            NSLocalizedString("REMOVE_ALL_DOWNLOADS"),
                            systemImage: "trash"
                        )
                    }
                }
            } label: {
                MoreIcon()
            }
        } else {
            DoneButton {
                withAnimation {
                    editMode = .inactive
                }
            }
        }

    }

    static nonisolated func == (lhs: RightNavbarButton, rhs: RightNavbarButton) -> Bool {
        lhs.bookmarked == rhs.bookmarked
            && lhs.hasCategories == rhs.hasCategories
            && lhs.url == rhs.url
            && lhs.hasDownloads == rhs.hasDownloads
            && lhs.isEditing == rhs.isEditing
    }
}

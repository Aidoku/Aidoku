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
    let source: AidokuRunner.Source?

    @StateObject private var viewModel: ViewModel

    @State private var editMode = EditMode.inactive
    @State private var selectedChapters = Set<String>()

    @State private var showingCoverView = false
    @State private var showRemoveAllConfirm = false
    @State private var showConnectionAlert = false

    @State private var descriptionExpanded = false

    @State private var loadingAlert: UIAlertController?

    private var path: NavigationCoordinator

    init(source: AidokuRunner.Source, manga: AidokuRunner.Manga, path: NavigationCoordinator) {
        self.source = source
        self._viewModel = StateObject(wrappedValue: ViewModel(source: source, manga: manga))
        self.path = path
    }

    var body: some View {
        let list = List(selection: $selectedChapters) {
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

                if !viewModel.chapters.isEmpty {
                    VStack {
                        Divider() // final, full width separator
                        Color.clear.frame(height: 28) // padding for bottom of list
                    }
                    .padding(.top, {
                        // add a little spacing above on ios 15, since the separator ends up hidden
                        if #available(iOS 16.0, *) { 0 } else { 0.5 }
                    }())
                    .listRowSeparator(.hidden)
                    .listRowInsets(.zero)
                }
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
        .confirmationDialog(
            NSLocalizedString("REMOVE_ALL_DOWNLOADS"),
            isPresented: $showRemoveAllConfirm,
            actions: {
                Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                Button(NSLocalizedString("REMOVE"), role: .destructive) {
                    DownloadManager.shared.deleteChapters(for: viewModel.manga.toOld())
                }
            },
            message: {
                Text(NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM"))
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
                source: source,
                manga: viewModel.manga
            )
        }
        .task {
            await viewModel.fetchDetails()
        }
        .onChange(of: editMode) { mode in
            guard let navigationController = path.rootViewController?.navigationController
            else { return }
            if mode == .active {
                UIView.animate(withDuration: 0.3) {
                    navigationController.isToolbarHidden = false
                    navigationController.toolbar.alpha = 1
                    
                }
            } else {
                UIView.animate(withDuration: 0.3) {
                    navigationController.toolbar.alpha = 0
                    
                } completion: { _ in
                    navigationController.isToolbarHidden = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackItemAdded)) { output in
            guard let item = output.object as? TrackItem else { return }
            Task {
                if let chapterNum = await viewModel.checkTrackerSync(item: item) {
                    syncWithTracker(chapterNum: chapterNum)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncTrackItem)) { output in
            guard let item = output.object as? TrackItem else { return }
            Task {
                if let chapterNum = await viewModel.checkTrackerSync(item: item) {
                    syncWithTracker(chapterNum: chapterNum)
                }
            }
        }
        .environment(\.editMode, $editMode)

    
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

extension MangaView {
    var headerView: some View {
        ZStack {
            MangaDetailsHeaderView(
                source: source,
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
                onTrackerButtonPressed: {
                    let vc = TrackerModalViewController(manga: viewModel.manga.toOld())
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

    @ViewBuilder
    func viewForChapter(_ chapter: AidokuRunner.Chapter, index: Int) -> some View {
        let last = index == viewModel.chapters.count - 1
        let downloaded = viewModel.downloadStatus[chapter.key] == .finished
        let locked = chapter.locked && !downloaded
        let opacity: Double = if #available(iOS 17.0, *), locked {
            0.5
        } else {
            1
        }

        ChapterCellView(
            source: source,
            sourceKey: viewModel.manga.sourceKey,
            chapter: chapter,
            read: viewModel.readingHistory[chapter.key]?.page == -1,
            page: viewModel.readingHistory[chapter.key]?.page,
            downloaded: downloaded,
            downloadProgress: viewModel.downloadProgress[chapter.key],
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
            contextMenu(chapter: chapter, index: index, last: last)
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
    func contextMenu(chapter: AidokuRunner.Chapter, index: Int, last: Bool) -> some View {
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
                let oldChapter = chapter.toOld(
                    sourceId: viewModel.manga.sourceKey,
                    mangaId: viewModel.manga.key
                )
                let downloadStatus = DownloadManager.shared.getDownloadStatus(for: oldChapter)
                if downloadStatus == .finished {
                    Button(role: .destructive) {
                        DownloadManager.shared.delete(chapters: [oldChapter])
                    } label: {
                        Label(NSLocalizedString("REMOVE_DOWNLOAD"), systemImage: "trash")
                    }
                } else if downloadStatus == .downloading {
                    Button(role: .destructive) {
                        DownloadManager.shared.cancelDownload(for: oldChapter)
                    } label: {
                        Label(NSLocalizedString("CANCEL_DOWNLOAD"), systemImage: "xmark")
                    }
                } else {
                    Button {
                        let downloadOnlyOnWifi = UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi")
                        if
                            downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi
                                || !downloadOnlyOnWifi
                        {
                            DownloadManager.shared.download(
                                chapters: [oldChapter],
                                manga: viewModel.manga.toOld()
                            )
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
            if !last {
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
        if editMode == .inactive {
            Menu {
                Menu(NSLocalizedString("MARK_ALL")) {
                    Button {
                        // only show loading indicator for a larger number of chapters
                        if viewModel.chapters.count > 100 {
                            showLoadingIndicator()
                        }
                        Task {
                            await viewModel.markRead(chapters: viewModel.chapters)
                            hideLoadingIndicator()
                        }
                    } label: {
                        Label(NSLocalizedString("READ"), systemImage: "eye")
                    }
                    Button {
                        if viewModel.chapters.count > 100 {
                            showLoadingIndicator()
                        }
                        Task {
                            await viewModel.markUnread(chapters: viewModel.chapters)
                            hideLoadingIndicator()
                        }
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
                if viewModel.bookmarked {
                    if !CoreDataManager.shared.getCategories(sorted: false).isEmpty {
                        Button {
                            path.present(
                                UINavigationController(
                                    rootViewController: CategorySelectViewController(
                                        manga: viewModel.manga
                                    )
                                )
                            )
                        } label: {
                            Label(NSLocalizedString("EDIT_CATEGORIES"), systemImage: "folder.badge.gearshape")
                        }
                    }
                    Button {
                        let migrateView = MigrateMangaView(manga: [viewModel.manga.toOld()])
                        path.present(UIHostingController(
                            rootView: SwiftUINavigationView(rootView: migrateView)
                        ))
                    } label: {
                        Label(NSLocalizedString("MIGRATE"), systemImage: "arrow.left.arrow.right")
                    }
                }
                if let url = viewModel.manga.url {
                    Button {
                        showShareSheet(url: url)
                    } label: {
                        Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                    }
                }

                if DownloadManager.shared.hasDownloadedChapter(
                    sourceId: viewModel.manga.sourceKey,
                    mangaId: viewModel.manga.key
                ) {
                    Divider()
                    Button(role: .destructive) {
                        showRemoveAllConfirm = true
                    } label: {
                        Label(
                            NSLocalizedString("REMOVE_ALL_DOWNLOADS"),
                            systemImage: "trash"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        } else {
            Button {
                withAnimation {
                    editMode = .inactive
                }
            } label: {
                Text(NSLocalizedString("DONE")).bold()
            }
        }
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

    var toolbarDownloadButton: some View {
        Button(NSLocalizedString("DOWNLOAD")) {
            let downloadChapters = selectedChapters
                .compactMap { id in
                    viewModel.chapters.first(where: { $0.key == id })?
                        .toOld(
                            sourceId: viewModel.manga.sourceKey,
                            mangaId: viewModel.manga.key
                        )
                }
                .filter { !DownloadManager.shared.isChapterDownloaded(chapter: $0) }
                .sorted { $0.sourceOrder > $1.sourceOrder }

            let downloadOnlyOnWifi = UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi")
            if
                downloadOnlyOnWifi && Reachability.getConnectionType() == .wifi
                    || !downloadOnlyOnWifi
            {
                DownloadManager.shared.download(
                    chapters: downloadChapters,
                    manga: viewModel.manga.toOld()
                )
            } else {
                showConnectionAlert = true
            }
            withAnimation {
                editMode = .inactive
            }
        }
        .disabled(viewModel.manga.isLocal() || selectedChapters.isEmpty)
    }
}

extension MangaView {
    func openReaderView(chapter: AidokuRunner.Chapter) {
        let readerController = ReaderViewController(
            source: source,
            manga: viewModel.manga,
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

    func syncWithTracker(chapterNum: Float) {
        // there's a bug where swiftui alert isn't shown so using uikit alert instead
        let alert = UIAlertController(
            title: NSLocalizedString("SYNC_WITH_TRACKER"),
            message: String(format: NSLocalizedString("SYNC_WITH_TRACKER_INFO"), chapterNum),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel) { _ in })

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
            guard
                let chapters = viewModel.manga.chapters,
                let lastReadChapter = chapters.firstIndex(where: {
                    $0.chapterNumber != nil && floor($0.chapterNumber!) <= chapterNum
                })
            else {
                return
            }
            let syncChapters = Array(chapters[lastReadChapter...])
            Task {
                await viewModel.markRead(chapters: syncChapters)
            }
        })

        path.present(alert)
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
    let downloaded: Bool
    let downloadProgress: Float?

    var onPressed: (() -> Void)?
    var contextMenu: (() -> T)?

    private var locked: Bool {
        chapter.locked && !downloaded
    }

    var body: some View {
        Button {
            onPressed?()
        } label: {
            HStack {
                ChapterTableCell(
                    source: source,
                    sourceKey: sourceKey,
                    chapter: chapter,
                    read: read,
                    page: page,
                    downloaded: downloaded,
                    downloadProgress: downloadProgress
                )
            }
        }
        .tint(.primary)
        .contextMenu {
            if !locked {
                contextMenu?()
            }
        }
    }

    static func == (lhs: ChapterCellView<T>, rhs: ChapterCellView<T>) -> Bool {
        lhs.chapter == rhs.chapter
            && lhs.read == rhs.read
            && lhs.page == rhs.page
            && lhs.downloaded == rhs.downloaded
            && lhs.downloadProgress == rhs.downloadProgress
    }
}

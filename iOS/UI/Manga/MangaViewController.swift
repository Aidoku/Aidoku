//
//  MangaViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/30/22.
//

import UIKit
import SwiftUI
import SafariServices

class MangaViewController: BaseTableViewController {

    let viewModel = MangaViewModel()
    lazy var dataSource = makeDataSource()

    var manga: Manga
    private let scrollToChapter: Chapter?

    lazy var headerView = MangaDetailHeaderView()
    private lazy var refreshControl = UIRefreshControl()
    private lazy var splitScrollView = UIScrollView() // ipad only

    private var storedTabBarAppearance: UITabBarAppearance?

    override var tableViewStyle: UITableView.Style {
        UIDevice.current.userInterfaceIdiom == .pad ? .plain : .grouped // use sticky header on ipad
    }

    init(manga: Manga, chapterList: [Chapter] = [], scrollTo: Chapter? = nil) {
        self.manga = manga
        self.scrollToChapter = scrollTo
        self.viewModel.fullChapterList = chapterList
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        super.configure()

        title = nil
        navigationItem.largeTitleDisplayMode = .never

        // load manga from db
        if let cachedManga = CoreDataManager.shared.getManga(sourceId: manga.sourceId, mangaId: manga.id) {
            manga = manga.copy(from: cachedManga.toManga())
        }

        // load filters before tableView init
        let filters = CoreDataManager.shared.getMangaChapterFilters(sourceId: manga.sourceId, mangaId: manga.id)
        viewModel.sortMethod = .init(flags: filters.flags)
        viewModel.sortAscending = filters.flags & ChapterFlagMask.sortAscending != 0
        viewModel.sortMethod = .init(flags: filters.flags)
        viewModel.filters = ChapterFilterOption.parseOptions(flags: filters.flags)
        viewModel.langFilter = filters.language

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.dataSource = dataSource
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ChapterCell")
        tableView.register(
            UITableViewHeaderFooterView.self,
            forHeaderFooterViewReuseIdentifier: "ChapterListHeader"
        )
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.backgroundColor = .systemBackground
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)

        headerView.configure(with: manga)
        headerView.delegate = self
        headerView.translatesAutoresizingMaskIntoConstraints = false

        if UIDevice.current.userInterfaceIdiom == .pad {
            splitScrollView.addSubview(headerView)

            splitScrollView.refreshControl = refreshControl
            splitScrollView.delaysContentTouches = false
            splitScrollView.backgroundColor = .systemBackground
            splitScrollView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(splitScrollView)
        } else {
            headerView.sizeChangeListener = self
            tableView.refreshControl = refreshControl
            tableView.tableHeaderView = UIView()
            tableView.tableHeaderView!.translatesAutoresizingMaskIntoConstraints = false
            tableView.tableHeaderView!.addSubview(headerView)
        }

        DispatchQueue.main.async {
            self.updateNavbarButtons()
        }
        updateDataSource() // set "no chapters" header

        Task {
            // load details if not in library
            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.manga.sourceId,
                    mangaId: self.manga.id,
                    context: context
                )
            }
            if !inLibrary, let source = SourceManager.shared.source(for: manga.sourceId) {
                let newManga = try? await source.getMangaDetails(manga: manga)
                if let newManga = newManga {
                    manga = manga.copy(from: newManga)
                }
                headerView.configure(with: manga)
            }

            await viewModel.loadHistory(manga: manga)
            await viewModel.loadChapterList(manga: manga)
            viewModel.sortChapters()
            updateDataSource()
            updateReadButton()

            // scroll to `scrollToChapter`
            if
                let chapter = scrollToChapter,
                let indexPath = dataSource.indexPath(for: chapter)
            {
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .middle)
                try? await Task.sleep(nanoseconds: 500 * 1000000)
                self.tableView.deselectRow(at: indexPath, animated: true)
            }

            if !UserDefaults.standard.bool(forKey: "General.incognitoMode") {
                await MangaUpdateManager.shared.viewAllUpdates(of: manga)
            }
        }
    }

    override func constrain() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            NSLayoutConstraint.activate([
                splitScrollView.topAnchor.constraint(equalTo: view.topAnchor),
                splitScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                splitScrollView.leftAnchor.constraint(equalTo: view.leftAnchor),
                splitScrollView.widthAnchor.constraint(equalToConstant: 360),

                headerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
                headerView.topAnchor.constraint(equalTo: splitScrollView.topAnchor),
                headerView.centerXAnchor.constraint(equalTo: splitScrollView.centerXAnchor),
                headerView.widthAnchor.constraint(equalTo: splitScrollView.widthAnchor),

                tableView.topAnchor.constraint(equalTo: view.topAnchor),
                tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                tableView.leftAnchor.constraint(equalTo: splitScrollView.rightAnchor),
                tableView.rightAnchor.constraint(equalTo: view.rightAnchor)
            ])
        } else {
            super.constrain() // table view constraints
            NSLayoutConstraint.activate([
                headerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
                headerView.widthAnchor.constraint(equalTo: tableView.widthAnchor),
                tableView.tableHeaderView!.heightAnchor.constraint(equalTo: headerView.heightAnchor),
                tableView.tableHeaderView!.widthAnchor.constraint(equalTo: headerView.widthAnchor)
            ])
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    override func observe() {
        // reload chapter list (triggered on filtering)
        addObserver(forName: "reloadChapterList") { [weak self] _ in
            guard let self = self else { return }
            self.updateReadButton()
            self.updateDataSource()
        }
        // update library status
        addObserver(forName: "addToLibrary") { [weak self] notification in
            guard
                let self = self,
                let manga = notification.object as? Manga,
                manga == self.manga
            else { return }
            Task { @MainActor in
                self.headerView.reloadBookmarkButton(inLibrary: true)
            }
        }
        // update reading history stored in view model
        addObserver(forName: "updateHistory") { [weak self] _ in
            guard let self = self else { return }
            Task {
                await self.viewModel.loadHistory(manga: self.manga)
                self.updateReadButton()
                self.updateDataSource()
            }
        }
        addObserver(forName: "historyAdded") { [weak self] notification in
            guard let self = self, let chapters = notification.object as? [Chapter] else { return }
            Task {
                self.viewModel.addHistory(for: chapters)
                self.reloadCells(for: chapters)
                self.updateReadButton()
            }
        }
        addObserver(forName: "historyRemoved") { [weak self] notification in
            guard let self = self else { return }
            Task {
                if let chapters = notification.object as? [Chapter] {
                    self.viewModel.removeHistory(for: chapters)
                    self.reloadCells(for: chapters)
                } else if
                    let manga = notification.object as? Manga,
                    manga.id == self.manga.id && manga.sourceId == self.manga.sourceId
                {
                    self.viewModel.readingHistory = [:]
                    self.updateDataSource()
                }
                self.updateReadButton()
            }
        }
        addObserver(forName: "historySet") { [weak self] notification in
            guard
                let self = self,
                let item = notification.object as? (chapter: Chapter, page: Int),
                self.viewModel.readingHistory[item.chapter.id]?.page != -1
            else { return }
            Task {
                self.viewModel.readingHistory[item.chapter.id] = (page: item.page, date: Int(Date().timeIntervalSince1970))
                self.reloadCells(for: [item.chapter])
                self.updateReadButton()
            }
        }
        // update tracking state
        addObserver(forName: "updateTrackers") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.headerView.reloadTrackerButton()
            }
        }
        // check for local tracker sync
        let checkSyncBlock: (Notification) -> Void = { [weak self] notification in
            guard
                let self = self,
                let item = notification.object as? TrackItem,
                item.mangaId == self.manga.id && item.sourceId == self.manga.sourceId,
                let tracker = TrackerManager.shared.getTracker(id: item.trackerId)
            else { return }
            Task {
                let latestChapterNum = self.viewModel.chapterList.max {
                    $0.chapterNum ?? -1 > $1.chapterNum ?? -1
                }?.chapterNum ?? -1
                let lastReadChapterNum = self.viewModel.chapterList.first {
                    self.viewModel.readingHistory[$0.id]?.page ?? 0 == -1
                }?.chapterNum ?? 0 // if not started, 0
                let hasUnreadChapters = self.viewModel.chapterList.contains {
                    self.viewModel.readingHistory[$0.id] == nil
                }
                let trackerState = await tracker.getState(trackId: item.id)

                if let trackerLastReadChapter = trackerState.lastReadChapter {
                    // check if latest read chapter is below tracker last read
                    var shouldSync = (lastReadChapterNum < trackerLastReadChapter)
                        // check if there are chapters to actually mark read
                        && (latestChapterNum >= trackerLastReadChapter || hasUnreadChapters)

                    if !shouldSync && hasUnreadChapters {
                        // see if there are unread chapters under the last read that are unread and below tracker last read
                        shouldSync = self.viewModel.chapterList.contains {
                            self.viewModel.readingHistory[$0.id] == nil
                            && $0.chapterNum ?? 0 < trackerLastReadChapter
                        }
                    }

                    if shouldSync {
                        // ask to sync
                        self.syncWithTracker(chapterNum: trackerLastReadChapter)
                    }
                }
            }
        }
        addObserver(forName: "trackItemAdded", using: checkSyncBlock)
        addObserver(forName: "syncTrackItem", using: checkSyncBlock)

        // check for manga migration
        addObserver(forName: "migratedManga") { [weak self] notification in
            guard
                let self = self,
                let migration = notification.object as? (from: Manga, to: Manga),
                migration.from.id == self.manga.id && migration.from.sourceId == self.manga.sourceId
            else { return }
            Task {
                self.manga = migration.to
                self.refresh()
            }
        }

        let removeDownloadBlock: (Notification) -> Void = { [weak self] notification in
            guard let self = self else { return }
            var chapter: Chapter?
            if let chapterCast = notification.object as? Chapter {
                chapter = chapterCast
            } else if let download = notification.object as? Download, let chapterCast = download.chapter {
                chapter = chapterCast
            }
            Task { @MainActor in
                if let chapter {
                    self.viewModel.downloadProgress.removeValue(forKey: chapter.id)
                    self.reloadCells(for: [chapter])
                    if self.viewModel.hasDownloadFilter {
                        self.viewModel.filterChapterList()
                        self.updateDataSource()
                    }
                }
                self.updateNavbarButtons()
            }
        }
        let removeDownloadsBlock: (Notification) -> Void = { [weak self] notification in
            guard let self = self else { return }
            Task { @MainActor in
                if let chapters = notification.object as? [Chapter] {
                    for chapter in chapters {
                        self.viewModel.downloadProgress.removeValue(forKey: chapter.id)
                    }
                    self.reloadCells(for: chapters)
                    if self.viewModel.hasDownloadFilter {
                        self.viewModel.filterChapterList()
                        self.updateDataSource()
                    }
                } else if
                    let manga = notification.object as? Manga,
                    manga.id == self.manga.id && manga.sourceId == self.manga.sourceId
                { // all chapters
                    self.viewModel.downloadProgress = [:]
                    if self.viewModel.hasDownloadFilter {
                        self.viewModel.filterChapterList()
                    }
                    self.updateDataSource()
                }
            }
        }

        // listen for downloads
        addObserver(forName: "downloadsQueued") { [weak self] notification in
            guard
                let self = self,
                let downloads = notification.object as? [Download]
            else { return }
            let chapters = downloads.compactMap { $0.chapter }
            Task { @MainActor in
                for chapter in chapters {
                    self.viewModel.downloadProgress[chapter.id] = 0
                }
                self.reloadCells(for: chapters)
            }
        }
        addObserver(forName: "downloadProgressed") { [weak self] notification in
            guard
                let self = self,
                let download = notification.object as? Download,
                let chapter = download.chapter
            else { return }
            Task { @MainActor in
                self.viewModel.downloadProgress[chapter.id] = Float(download.progress) / Float(download.total)
                self.reloadCells(for: [chapter])
            }
        }
        addObserver(forName: "downloadFinished", using: removeDownloadBlock)
        addObserver(forName: "downloadRemoved", using: removeDownloadBlock)
        addObserver(forName: "downloadCancelled", using: removeDownloadBlock)
        addObserver(forName: "downloadsRemoved", using: removeDownloadsBlock)
        addObserver(forName: "downloadsCancelled", using: removeDownloadsBlock)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        headerView.scaleTitle()

        // fix tab bar background turning clear when presenting
        if #available(iOS 15.0, *) {
            storedTabBarAppearance = navigationController?.tabBarController?.tabBar.scrollEdgeAppearance
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            navigationController?.tabBarController?.tabBar.scrollEdgeAppearance = tabBarAppearance
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // reset tab bar background fix
        if #available(iOS 15.0, *) {
            navigationController?.tabBarController?.tabBar.scrollEdgeAppearance = storedTabBarAppearance
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if tableView.tableHeaderView?.subviews.first is MangaDetailHeaderView {
            tableView.tableHeaderView?.layoutIfNeeded()
            tableView.tableHeaderView = tableView.tableHeaderView // needed in order to update table view offset
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.headerView.scaleTitle()
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        updateNavbarButtons()
        updateToolbar()
    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
    }

    func openReaderView(chapter: Chapter) {
        let readerController = ReaderViewController(
            chapter: chapter,
            chapterList: viewModel.getOrderedChapterList(),
            defaultReadingMode: ReadingMode(rawValue: manga.viewer.rawValue)
        )
        let navigationController = ReaderNavigationController(rootViewController: readerController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    /// Marks given chapters as read.
    func markRead(chapters: [Chapter]) async {
        await HistoryManager.shared.addHistory(chapters: chapters)
    }

    /// Marks given chapters as unread.
    func markUnread(chapters: [Chapter]) async {
        await HistoryManager.shared.removeHistory(chapters: chapters)
    }

    func syncWithTracker(chapterNum: Float) {
        let alert = UIAlertController(
            title: NSLocalizedString("SYNC_WITH_TRACKER", comment: ""),
            message: String(format: NSLocalizedString("SYNC_WITH_TRACKER_INFO", comment: ""), chapterNum),
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel) { _ in })

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            let chapters = self.viewModel.chapterList.filter {
                floor($0.chapterNum ?? -1) <= chapterNum
            }
            Task {
                await self.markRead(chapters: chapters)
            }
        })

        let presenter = presentedViewController ?? self
        presenter.present(alert, animated: true)
    }

    func migrateManga() {
        let migrateView = MigrateMangaView(manga: [manga])
        present(UIHostingController(rootView: SwiftUINavigationView(rootView: AnyView(migrateView))), animated: true)
    }

    @objc func refresh(_ refreshControl: UIRefreshControl? = nil) {
        guard Reachability.getConnectionType() != .none else {
            refreshControl?.endRefreshing()
            return
        }
        Task {
            if let source = SourceManager.shared.source(for: manga.sourceId) {
                let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.hasLibraryManga(
                        sourceId: self.manga.sourceId,
                        mangaId: self.manga.id,
                        context: context
                    )
                }
                await withTaskGroup(of: Void.self) { group in
                    // update manga details
                    group.addTask {
                        let oldManga = await self.manga
                        let newManga = try? await source.getMangaDetails(manga: oldManga)
                        if let newManga = newManga {
                            let updatedManga = oldManga.copy(from: newManga)
                            await MainActor.run {
                                self.manga = updatedManga
                            }
                            // update in db
                            if inLibrary {
                                await CoreDataManager.shared.updateMangaDetails(manga: updatedManga)
                            }
                        }
                    }
                    // update chapters
                    group.addTask {
                        let manga = await self.manga
                        if let chapterList = try? await source.getChapterList(manga: manga) {
                            await MainActor.run {
                                self.viewModel.fullChapterList = chapterList
                            }
                            // update in db
                            if inLibrary {
                                let langFilter = await self.viewModel.langFilter
                                await CoreDataManager.shared.container.performBackgroundTask { context in
                                    let newChapters = CoreDataManager.shared.setChapters(
                                        chapterList,
                                        sourceId: manga.sourceId,
                                        mangaId: manga.id,
                                        context: context
                                    )
                                    // update manga updates
                                    for chapter in newChapters
                                    where langFilter != nil ? chapter.lang == langFilter : true
                                    {
                                        CoreDataManager.shared.createMangaUpdate(
                                            sourceId: manga.sourceId,
                                            mangaId: manga.id,
                                            chapterObject: chapter,
                                            context: context
                                        )
                                    }
                                    try? context.save()
                                }
                            }
                        }
                    }
                }
            }
            headerView.configure(with: manga)
            await viewModel.loadHistory(manga: manga)
            viewModel.filterChapterList()
            updateDataSource()
            updateReadButton()
            refreshControl?.endRefreshing()
        }
    }
}

extension MangaViewController {

    @objc func selectAllRows() {
        for row in 0..<tableView.numberOfRows(inSection: 0) {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
        updateNavbarButtons()
        updateToolbar()
    }

    @objc func deselectAllRows() {
        for row in 0..<tableView.numberOfRows(inSection: 0) {
            tableView.deselectRow(at: IndexPath(row: row, section: 0), animated: false)
        }
        updateNavbarButtons()
        updateToolbar()
    }

    @objc func downloadSelectedChapters() {
        let chapters = (tableView.indexPathsForSelectedRows?.compactMap {
            self.dataSource.itemIdentifier(for: $0)
        } ?? [])
            .filter { !DownloadManager.shared.isChapterDownloaded(chapter: $0) }
            .sorted { $0.sourceOrder > $1.sourceOrder }

        if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") &&
            Reachability.getConnectionType() == .wifi ||
            !UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
            DownloadManager.shared.download(chapters: chapters, manga: manga)
        } else {
            self.presentAlert(
                title: NSLocalizedString("NO_WIFI_ALERT_TITLE", comment: ""),
                message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE", comment: "")
            )
        }
        setEditing(false, animated: true)
    }

    @objc func deleteSelectedChapters() {
        let chapters = (tableView.indexPathsForSelectedRows?.compactMap {
            self.dataSource.itemIdentifier(for: $0)
        } ?? [])
        confirmAction(
            title: NSLocalizedString("REMOVE_DOWNLOADS", comment: ""),
            message: NSLocalizedString("REMOVE_DOWNLOADS_CONFIRM", comment: ""),
            continueActionName: NSLocalizedString("REMOVE", comment: "")
        ) {
            DownloadManager.shared.delete(chapters: chapters)
            self.reloadCells(for: chapters)
            self.setEditing(false, animated: true)
        }
    }
}

// MARK: View Updating
extension MangaViewController {

    private func updateReadButton() {
        let nextChapter = viewModel.getNextChapter()
        switch nextChapter {
        case .none:
            return
        case .allRead:
            headerView.updateReadButtonTitle(allRead: true)
        case .chapter(let nextChapter):
            let continueReading = viewModel.readingHistory[nextChapter.id]?.date ?? 0 > 0
            headerView.updateReadButtonTitle(nextChapter: nextChapter, continueReading: continueReading)
        }
    }

    private func makeMenu() async -> [UIMenuElement] {
        var menus = [UIMenu]()
        var actions: [UIMenuElement] = [
            UIMenu(title: NSLocalizedString("MARK_ALL", comment: ""), image: nil, children: [
                // read chapters
                UIAction(title: NSLocalizedString("READ", comment: ""), image: UIImage(systemName: "eye")) { _ in
                    self.showLoadingIndicator()
                    Task {
                        await self.markRead(chapters: self.viewModel.chapterList)
                        self.hideLoadingIndicator()
                    }
                },
                // unread chapters
                UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: UIImage(systemName: "eye.slash")) { _ in
                    self.showLoadingIndicator()
                    Task {
                        await self.markUnread(chapters: self.viewModel.chapterList)
                        self.hideLoadingIndicator()
                    }
                }
            ]),
            // Select chapters
            UIAction(
                title: NSLocalizedString("SELECT_CHAPTERS", comment: ""),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in
                self?.setEditing(true, animated: true)
            }
        ]

        // add edit categories button if in library and have categories
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let inLibrary = CoreDataManager.shared.hasLibraryManga(
                sourceId: self.manga.sourceId,
                mangaId: self.manga.id,
                context: context
            )
            if inLibrary {
                if !CoreDataManager.shared.getCategories(sorted: false, context: context).isEmpty {
                    actions.append(UIAction(
                        title: NSLocalizedString("EDIT_CATEGORIES", comment: ""),
                        image: UIImage(systemName: "folder.badge.gearshape")
                    ) { [weak self] _ in
                        guard let self = self else { return }
                        self.present(
                            UINavigationController(rootViewController: CategorySelectViewController(
                                manga: self.manga,
                                chapterList: self.viewModel.chapterList
                            )),
                            animated: true
                        )
                    })
                }
                actions.append(UIAction(
                    title: NSLocalizedString("MIGRATE", comment: ""),
                    image: UIImage(systemName: "arrow.left.arrow.right")
                ) { [weak self] _ in
                    self?.migrateManga()
                })
            }
        }

        // add share button if manga has a url
        if let url = manga.url {
            actions.append(UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
                guard let self = self else { return }

                let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activityViewController.popoverPresentationController?.sourceView = self.view

                if let navigationController = self.navigationController {
                    let x = navigationController.navigationBar.frame.midX * 0.95
                    activityViewController.popoverPresentationController?.sourceRect = navigationController.navigationBar.frame.offsetBy(dx: x, dy: 0)
                }

                self.present(activityViewController, animated: true)
            })
        }

        menus.append(UIMenu(title: "", options: .displayInline, children: actions))

        // add remove all downloads button if downloads exist
        if DownloadManager.shared.hasDownloadedChapter(sourceId: manga.sourceId, mangaId: manga.id) {
            menus.append(UIMenu(title: "", options: .displayInline, children: [
                UIAction(
                    title: NSLocalizedString("REMOVE_ALL_DOWNLOADS", comment: ""),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    guard let self = self else { return }
                    self.confirmAction(
                        title: NSLocalizedString("REMOVE_ALL_DOWNLOADS", comment: ""),
                        message: NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM", comment: ""),
                        continueActionName: NSLocalizedString("REMOVE", comment: "")
                    ) {
                        DownloadManager.shared.deleteChapters(for: self.manga)
                        self.reloadCells(for: self.viewModel.chapterList)
                        self.updateNavbarButtons()
                    }
                }
            ]))
        }

        return menus
    }

    func updateNavbarButtons() {
        if tableView.isEditing {
            Task { @MainActor in
                rootNavigation.navigationItem.hidesBackButton = true
                if tableView.indexPathsForSelectedRows?.count ?? 0 == tableView.numberOfRows(inSection: 0) {
                    rootNavigation.navigationItem.leftBarButtonItem = UIBarButtonItem(
                        title: NSLocalizedString("DESELECT_ALL", comment: ""),
                        style: .plain,
                        target: self,
                        action: #selector(deselectAllRows)
                    )
                } else {
                    rootNavigation.navigationItem.leftBarButtonItem = UIBarButtonItem(
                        title: NSLocalizedString("SELECT_ALL", comment: ""),
                        style: .plain,
                        target: self,
                        action: #selector(selectAllRows)
                    )
                }
                rootNavigation.navigationItem.rightBarButtonItem = UIBarButtonItem(
                    barButtonSystemItem: .done,
                    target: self,
                    action: #selector(stopEditing)
                )
            }
        } else {
            rootNavigation.navigationItem.hidesBackButton = false
            rootNavigation.navigationItem.leftBarButtonItem = nil

            let menu: UIMenu
            if #available(iOS 15.0, *) { // make menu dynamic on ios 15
                if rootNavigation.navigationItem.rightBarButtonItem?.menu != nil { return }
                menu = UIMenu(title: "", children: [
                    UIDeferredMenuElement.uncached { [weak self] completion in
                        guard let self = self else {
                            completion([])
                            return
                        }
                        Task {
                            completion(await self.makeMenu())
                        }
                    }
                ])
            } else {
                menu = UIMenu(title: "", children: [
                    UIDeferredMenuElement { [weak self] completion in
                        guard let self = self else {
                            completion([])
                            return
                        }
                        Task {
                            completion(await self.makeMenu())
                        }
                    }
                ])
            }

            let moreButton = UIBarButtonItem(
                image: UIImage(systemName: "ellipsis"),
                style: .plain,
                target: self,
                action: nil
            )
            moreButton.menu = menu

            Task { @MainActor in
                rootNavigation.navigationItem.rightBarButtonItem = moreButton
            }
        }
    }

    // update toolbar items (when editing)
    func updateToolbar() {
        if tableView.isEditing {
            // show toolbar
            if rootNavigation.navigationController?.isToolbarHidden ?? false {
                UIView.animate(withDuration: 0.3) {
                    self.rootNavigation.navigationController?.isToolbarHidden = false
                    self.rootNavigation.navigationController?.toolbar.alpha = 1
                }
            }

            let markButton = UIBarButtonItem(
                title: NSLocalizedString("MARK", comment: ""),
                style: .plain,
                target: self,
                action: nil
            )
            var downloadButton = UIBarButtonItem(
                title: NSLocalizedString("DOWNLOAD", comment: ""),
                style: .plain,
                target: self,
                action: #selector(downloadSelectedChapters)
            )

            let selectedRows = tableView.indexPathsForSelectedRows ?? []

            if !selectedRows.isEmpty {
                let selectedChapters = selectedRows.compactMap {
                    self.dataSource.itemIdentifier(for: $0)
                }
                markButton.menu = UIMenu(
                    title: selectedRows.count > 1
                        ? String(format: NSLocalizedString("%i_CHAPTERS", comment: ""), selectedRows.count)
                        : NSLocalizedString("1_CHAPTER", comment: ""),
                    children: [
                        UIAction(
                            title: NSLocalizedString("UNREAD", comment: ""),
                            image: UIImage(systemName: "eye.slash")
                        ) { [weak self] _ in
                            guard let self = self else { return }
                            self.showLoadingIndicator()
                            Task {
                                await self.markUnread(chapters: selectedChapters)
                                self.hideLoadingIndicator()
                                self.setEditing(false, animated: true)
                            }
                        },
                        UIAction(
                            title: NSLocalizedString("READ", comment: ""),
                            image: UIImage(systemName: "eye")
                        ) { [weak self] _ in
                            guard let self = self else { return }
                            self.showLoadingIndicator()
                            Task {
                                await self.markRead(chapters: selectedChapters)
                                self.hideLoadingIndicator()
                                self.setEditing(false, animated: true)
                            }
                        }
                    ]
                )

                // switch download button to remove if all the selected chapters are downloaded
                let allChaptersDownloaded = !selectedChapters.contains(where: {
                    !DownloadManager.shared.isChapterDownloaded(chapter: $0)
                })
                if allChaptersDownloaded {
                    downloadButton = UIBarButtonItem(
                        title: NSLocalizedString("REMOVE", comment: ""),
                        style: .plain,
                        target: self,
                        action: #selector(deleteSelectedChapters)
                    )
                }
            }

            markButton.isEnabled = !selectedRows.isEmpty
            downloadButton.isEnabled = !selectedRows.isEmpty

            rootNavigation.toolbarItems = [
                markButton,
                UIBarButtonItem(systemItem: .flexibleSpace),
                downloadButton
            ]
        } else if !(self.rootNavigation.navigationController?.isToolbarHidden ?? true) {
            // fade out toolbar
            UIView.animate(withDuration: 0.3) {
                self.rootNavigation.navigationController?.toolbar.alpha = 0
            } completion: { _ in
                self.rootNavigation.navigationController?.isToolbarHidden = true
            }
        }
    }
}

// MARK: - Table View Delegate
extension MangaViewController {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !tableView.isEditing else {
            updateNavbarButtons()
            updateToolbar()
            return
        }
        if let chapter = dataSource.itemIdentifier(for: indexPath) {
            openReaderView(chapter: chapter)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateNavbarButtons()
            updateToolbar()
        }
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard
            let cell = tableView.dequeueReusableHeaderFooterView(withIdentifier: "ChapterListHeader")
        else { return nil }
        var config = ChapterListHeaderConfiguration()
        config.delegate = self
        config.chapterCount = viewModel.chapterList.count
        config.sortOption = viewModel.sortMethod
        config.sortAscending = viewModel.sortAscending
        config.filters = viewModel.filters
        config.langFilter = viewModel.langFilter
        config.sourceLangs = viewModel.getSourceDefaultLanguages(sourceId: manga.sourceId)
        cell.contentConfiguration = config
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let chapter = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            var actions: [UIMenuElement] = []

            // download action
            let downloadAction: UIMenuElement
            let downloadStatus = DownloadManager.shared.getDownloadStatus(for: chapter)
            if downloadStatus == .finished {
                downloadAction = UIAction(
                    title: NSLocalizedString("REMOVE_DOWNLOAD", comment: ""),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    DownloadManager.shared.delete(chapters: [chapter])
                    self.reloadCells(for: [chapter])
                }
            } else if downloadStatus == .downloading {
                downloadAction = UIAction(
                    title: NSLocalizedString("CANCEL_DOWNLOAD", comment: ""),
                    image: UIImage(systemName: "xmark"),
                    attributes: .destructive
                ) { _ in
                    DownloadManager.shared.cancelDownload(for: chapter)
                    self.reloadCells(for: [chapter])
                }
            } else {
                downloadAction = UIAction(
                    title: NSLocalizedString("DOWNLOAD", comment: ""),
                    image: UIImage(systemName: "arrow.down.circle")
                ) { _ in
                    if UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") &&
                        Reachability.getConnectionType() == .wifi ||
                        !UserDefaults.standard.bool(forKey: "Library.downloadOnlyOnWifi") {
                        DownloadManager.shared.download(chapters: [chapter], manga: self.manga)
                    } else {
                        self.presentAlert(
                            title: NSLocalizedString("NO_WIFI_ALERT_TITLE", comment: ""),
                            message: NSLocalizedString("NO_WIFI_ALERT_MESSAGE", comment: "")
                        )
                    }

                    self.reloadCells(for: [chapter])
                }
            }
            actions.append(UIMenu(title: "", options: .displayInline, children: [downloadAction]))

            // marking actions
            let history = self.viewModel.readingHistory[chapter.id] ?? (0, -1)
            if history.1 < 0 || history.0 != -1 { // not completed or has started
                actions.append(UIAction(
                    title: NSLocalizedString("MARK_READ", comment: ""),
                    image: UIImage(systemName: "eye")
                ) { _ in
                    Task {
                        await self.markRead(chapters: [chapter])
                    }
                })
            }
            if history.1 > 0 { // has read date
                actions.append(UIAction(
                    title: NSLocalizedString("MARK_UNREAD", comment: ""),
                    image: UIImage(systemName: "eye.slash")
                ) { _ in
                    Task {
                        await self.markUnread(chapters: [chapter])
                    }
                })
            }
            if indexPath.row != self.viewModel.chapterList.count - 1 { // not chapter at bottom
                actions.append(self.markPreviousSubmenu(at: indexPath))
            }

            // sharing action
            if let url = URL(string: chapter.url ?? "") {
                actions.append(UIMenu(title: "", options: .displayInline, children: [
                    UIAction(title: NSLocalizedString("SHARE", comment: ""),
                             image: UIImage(systemName: "square.and.arrow.up")
                    ) { _ in
                        let activityViewController = UIActivityViewController(
                            activityItems: [url],
                            applicationActivities: nil
                        )
                        activityViewController.popoverPresentationController?.sourceView = self.view

                        self.present(activityViewController, animated: true)
                    }
                ]))
            }
            return UIMenu(title: "", children: actions)
        }
    }

    /// Returns a "Mark Previous" submenu for the chapter cell at the specified index path.
    private func markPreviousSubmenu(at indexPath: IndexPath) -> UIMenu {
        UIMenu(title: NSLocalizedString("MARK_PREVIOUS", comment: ""), children: [
            UIAction(
                title: NSLocalizedString("READ", comment: ""),
                image: UIImage(systemName: "eye")
            ) { _ in
                let chapters = [Chapter](self.viewModel.chapterList[
                    indexPath.row..<self.viewModel.chapterList.count
                ])
                Task {
                    await self.markRead(chapters: chapters)
                }
            },
            UIAction(
                title: NSLocalizedString("UNREAD", comment: ""),
                image: UIImage(systemName: "eye.slash")
            ) { _ in
                let chapters = [Chapter](self.viewModel.chapterList[
                    indexPath.row..<self.viewModel.chapterList.count
                ])
                Task {
                    await self.markUnread(chapters: chapters)
                }
            }
        ])
    }
}

// MARK: - Data Source
extension MangaViewController {

    enum Section: Hashable {
        case chapters(count: Int)
    }

    private func makeDataSource() -> UITableViewDiffableDataSource<Section, Chapter> {
        UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, chapter in
            let cell = tableView.dequeueReusableCell(withIdentifier: "ChapterCell", for: indexPath)
            var config = ChapterCellConfiguration(chapter: chapter)
            let status = DownloadManager.shared.getDownloadStatus(for: chapter)
            config.downloaded = status == .finished
            if let history = self?.viewModel.readingHistory[chapter.id] {
                config.read = history.page == -1
                config.currentPage = config.read ? nil : history.0
            }
            if let downloadProgress = self?.viewModel.downloadProgress[chapter.id] {
                config.downloading = true
                config.downloadProgress = downloadProgress
            } else {
                config.downloading = status == .downloading || status == .queued
            }
            cell.contentConfiguration = config
            cell.backgroundColor = .systemBackground
            return cell
        }
    }

    private func updateHeader() {
        // refresh header without animation
        var snapshot = NSDiffableDataSourceSnapshot<Section, Chapter>()
        let sections = [Section.chapters(count: viewModel.chapterList.count)]
        let oldItems = dataSource.snapshot().itemIdentifiers
        snapshot.appendSections(sections)
        snapshot.appendItems(oldItems)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func updateDataSource() {
        updateHeader()

        let current = dataSource.snapshot()

        // refresh chapters
        var snapshot = NSDiffableDataSourceSnapshot<Section, Chapter>()
        snapshot.appendSections(current.sectionIdentifiers)
        snapshot.appendItems(viewModel.chapterList)
        dataSource.apply(
            snapshot,
            // skip animation if chapters are the same (needed when chapter is a class)
            animatingDifferences: current.itemIdentifiers != viewModel.chapterList
        )
    }

    func refreshDataSource() {
        updateHeader()

        // re-sort chapters
        var snapshot = NSDiffableDataSourceSnapshot<Section, Chapter>()
        snapshot.appendSections(dataSource.snapshot().sectionIdentifiers)
        snapshot.appendItems(viewModel.chapterList)
        dataSource.apply(snapshot, animatingDifferences: false)

        // refresh chapters for fade animation
        snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot)
    }

    func reloadCells(for chapters: [Chapter]) {
        var snapshot = dataSource.snapshot()
        guard !snapshot.itemIdentifiers.isEmpty else { return }
        // swap chapters with chapters in data store (not doing this results in "invalid item identifier" crash)
        let chapters = chapters.compactMap { chapter in
            snapshot.itemIdentifiers.first(where: { $0 == chapter })
        }
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems(chapters)
        } else {
            snapshot.reloadItems(chapters)
        }
        dataSource.apply(snapshot)
    }
}

// MARK: - Header View Delegate
extension MangaViewController: MangaDetailHeaderViewDelegate {

    // add to library
    func bookmarkPressed() {
        Task {
            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.hasLibraryManga(
                    sourceId: self.manga.sourceId,
                    mangaId: self.manga.id,
                    context: context
                )
            }
            if inLibrary {
                // remove from library
                await MangaManager.shared.removeFromLibrary(sourceId: manga.sourceId, mangaId: manga.id)
                headerView.reloadBookmarkButton(inLibrary: false)
            } else {
                // check if category select should open
                let categories = CoreDataManager.shared.getCategoryTitles()
                var shouldAskCategory = !categories.isEmpty
                if
                    let defaultCategory = UserDefaults.standard.stringArray(forKey: "Library.defaultCategory")?.first,
                    defaultCategory == "none" || categories.contains(defaultCategory)
                {
                    shouldAskCategory = false
                }
                if shouldAskCategory { // open category select view
                    present(
                        UINavigationController(rootViewController: CategorySelectViewController(
                            manga: manga,
                            chapterList: viewModel.chapterList
                        )),
                        animated: true
                    )
                } else { // add to library
                    // adjust tint ahead of delay
                    headerView.reloadBookmarkButton(inLibrary: true)
                    await MangaManager.shared.addToLibrary(manga: manga, chapters: viewModel.chapterList)
                }
            }
        }
    }

    // open category select view
    func bookmarkHeld() {
        present(UINavigationController(rootViewController: CategorySelectViewController(
            manga: manga,
            chapterList: viewModel.chapterList)
        ), animated: true)
    }

    // open tracker menu
    func trackerPressed() {
        let vc = TrackerModalViewController(manga: manga)
        vc.view.tintColor = view.tintColor
        vc.modalPresentationStyle = .overFullScreen
        present(vc, animated: false)
    }

    // open safari web view
    func safariPressed() {
        guard
            let url = manga.url,
            url.scheme == "https" || url.scheme == "http"
        else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    // copy manga link when holding down the web view button
    func safariHeld() {
        guard let url = manga.url else { return }
        UIPasteboard.general.string = url.absoluteString
        let alert = UIAlertController(
            title: NSLocalizedString("LINK_COPIED", comment: ""),
            message: NSLocalizedString("LINK_COPIED_TEXT", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    // open reader to next chapter
    func readPressed() {
        guard let chapter = headerView.nextChapter else { return }
        openReaderView(chapter: chapter)
    }

    // open full manga cover view
    func coverPressed() {
        let navigationController = UINavigationController(rootViewController: MangaCoverViewController(manga: manga))
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
}

// MARK: - Chapter Sort Delegate
extension MangaViewController: ChapterSortDelegate {

    func sortOptionChanged(_ newOption: ChapterSortOption) {
        viewModel.sortChapters(method: newOption)
        refreshDataSource()
        updateReadButton()
        Task {
            await viewModel.saveFilters(manga: manga)
        }
    }

    func sortAscendingChanged(_ newValue: Bool) {
        viewModel.sortChapters(ascending: newValue)
        refreshDataSource()
        updateReadButton()
        Task {
            await viewModel.saveFilters(manga: manga)
        }
    }

    func filtersChanged(_ newFilters: [ChapterFilterOption]) {
        Task {
            viewModel.filters = newFilters
            await viewModel.loadChapterList(manga: manga)
            refreshDataSource()
            updateReadButton()
            await viewModel.saveFilters(manga: manga)
        }
    }

    func langFilterChanged(_ newValue: String?) {
        Task {
            await viewModel.languageFilterChanged(newValue, manga: manga)
            refreshDataSource()
            updateReadButton()
        }
    }
}

// MARK: - Header Size Change Listener
extension MangaViewController: SizeChangeListenerDelegate {
    func sizeChanged(_ newSize: CGSize) {
        view.setNeedsLayout() // indirectly calls viewWillLayoutSubviews
    }
}

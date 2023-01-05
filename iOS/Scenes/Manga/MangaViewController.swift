//
//  MangaViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/30/22.
//

import UIKit
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
        viewModel.chapterList = chapterList
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

        updateNavbarButtons()
        updateDataSource() // set "no chapters" header

        Task {
            // load details if not in library
            let inLibrary = CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id)
            if !inLibrary, let source = SourceManager.shared.source(for: manga.sourceId) {
                let newManga = try? await source.getMangaDetails(manga: manga)
                if let newManga = newManga {
                    manga = manga.copy(from: newManga)
                }
                headerView.configure(with: manga)
            }

            await viewModel.loadHistory(manga: manga)
            await viewModel.loadChapterList(manga: manga)
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
        addObserver(forName: "updateHistory") { [weak self] notification in
            guard let self = self else { return }
            Task {
                await self.viewModel.loadHistory(manga: self.manga)
                self.updateReadButton()
                if let chapter = notification.object as? Chapter {
                    self.reloadCells(for: [chapter])
                }
            }
        }
        // update tracking state
        addObserver(forName: "updateTrackers") { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.headerView.reloadTrackerButton()
            }
        }

        let updateDownloadCellBlock: (Notification) -> Void = { [weak self] notification in
            guard let self = self else { return }
            var chapter: Chapter?
            if let chapterCast = notification.object as? Chapter {
                chapter = chapterCast
            } else if let download = notification.object as? Download, let chapterCast = download.chapter {
                chapter = chapterCast
            }
            Task { @MainActor in
                if let chapter = chapter {
                    self.viewModel.downloadProgress.removeValue(forKey: chapter.id)
                    self.reloadCells(for: [chapter])
                }
                self.updateNavbarButtons()
            }
        }
        let updateDownloadCellsBlock: (Notification) -> Void = { [weak self] notification in
            guard let self = self else { return }
            Task { @MainActor in
                if let chapters = notification.object as? [Chapter] {
                    for chapter in chapters {
                        self.viewModel.downloadProgress.removeValue(forKey: chapter.id)
                    }
                    self.reloadCells(for: chapters)
                } else if
                    let manga = notification.object as? Manga,
                    manga.id == self.manga.id && manga.sourceId == self.manga.sourceId
                { // all chapters
                    self.viewModel.downloadProgress = [:]
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
        addObserver(forName: "downloadFinished", using: updateDownloadCellBlock)
        addObserver(forName: "downloadRemoved", using: updateDownloadCellBlock)
        addObserver(forName: "downloadCancelled", using: updateDownloadCellBlock)
        addObserver(forName: "downloadsRemoved", using: updateDownloadCellsBlock)
        addObserver(forName: "downloadsCancelled", using: updateDownloadCellsBlock)
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

    // returns first chapter not completed, or falls back to last read chapter
    func getNextChapter() -> Chapter? {
        guard !viewModel.chapterList.isEmpty else { return nil }
        // get first chapter not completed
        let chapter = viewModel.chapterList.reversed().first(where: { viewModel.readingHistory[$0.id]?.page ?? 0 != -1 })
        if let chapter = chapter {
            return chapter
        }
        // get last read chapter
        let id = viewModel.readingHistory.max { a, b in a.value.date < b.value.date }?.key
        let lastRead: Chapter
        if let id = id, let match = viewModel.chapterList.first(where: { $0.id == id }) {
            lastRead = match
        } else {
            lastRead = viewModel.chapterList.last!
        }
        return lastRead
    }

    func updateReadButton() {
        guard let nextChapter = getNextChapter() else { return }
        headerView.continueReading = viewModel.readingHistory[nextChapter.id]?.date ?? 0 > 0
        headerView.nextChapter = nextChapter
    }

    func openReaderView(chapter: Chapter) {
        let readerController = ReaderViewController(chapter: chapter, chapterList: viewModel.chapterList)
        let navigationController = ReaderNavigationController(rootViewController: readerController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    @objc func refresh(_ refreshControl: UIRefreshControl) {
        Task {
            if let source = SourceManager.shared.source(for: manga.sourceId) {
                let inLibrary = CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id)
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
                        let chapterList = (try? await source.getChapterList(manga: manga)) ?? []
                        await MainActor.run {
                            self.viewModel.chapterList = chapterList
                        }
                        // update in db
                        if inLibrary {
                            await CoreDataManager.shared.container.performBackgroundTask { context in
                                CoreDataManager.shared.setChapters(
                                    chapterList,
                                    sourceId: manga.sourceId,
                                    mangaId: manga.id,
                                    context: context
                                )
                                try? context.save()
                            }
                        }
                    }
                }
            }
            headerView.configure(with: manga)
            await viewModel.loadHistory(manga: manga)
            updateDataSource()
            updateReadButton()
            refreshControl.endRefreshing()
        }
    }

    @objc func stopEditing() {
        setEditing(false, animated: true)
    }

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
        DownloadManager.shared.download(chapters: chapters, manga: manga)
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

    private func makeMenu() -> [UIMenuElement] {
        var menus = [UIMenu]()
        var actions = [
            UIAction(
                title: NSLocalizedString("SELECT_CHAPTERS", comment: ""),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in
                self?.setEditing(true, animated: true)
            }
        ]

        // add edit categories button if in library and have categories
        let inLibrary = CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id)
        if inLibrary, !CoreDataManager.shared.getCategories(sorted: false).isEmpty {
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

        // add share button if manga has a url
        if let url = manga.url {
            actions.append(UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { [weak self] _ in
                guard let self = self else { return }

                let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                activityViewController.popoverPresentationController?.sourceView = self.view

                self.present(activityViewController, animated: true, completion: nil)
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
                navigationItem.hidesBackButton = true
                if tableView.indexPathsForSelectedRows?.count ?? 0 == tableView.numberOfRows(inSection: 0) {
                    navigationItem.leftBarButtonItem = UIBarButtonItem(
                        title: NSLocalizedString("DESELECT_ALL", comment: ""),
                        style: .plain,
                        target: self,
                        action: #selector(deselectAllRows)
                    )
                } else {
                    navigationItem.leftBarButtonItem = UIBarButtonItem(
                        title: NSLocalizedString("SELECT_ALL", comment: ""),
                        style: .plain,
                        target: self,
                        action: #selector(selectAllRows)
                    )
                }
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(stopEditing))
            }
        } else {
            navigationItem.hidesBackButton = false
            navigationItem.leftBarButtonItem = nil

            let menu: UIMenu
            if #available(iOS 15.0, *) { // make menu dynamic on ios 15
                if navigationItem.rightBarButtonItem?.menu != nil { return }
                menu = UIMenu(title: "", children: [
                    UIDeferredMenuElement.uncached { [weak self] completion in
                        guard let self = self else {
                            completion([])
                            return
                        }
                        completion(self.makeMenu())
                    }
                ])
            } else {
                menu = UIMenu(title: "", children: [
                    UIDeferredMenuElement { [weak self] completion in
                        guard let self = self else {
                            completion([])
                            return
                        }
                        completion(self.makeMenu())
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
                navigationItem.rightBarButtonItem = moreButton
            }
        }
    }

    // update toolbar items (when editing)
    func updateToolbar() {
        if tableView.isEditing {
            // show toolbar
            if navigationController?.isToolbarHidden ?? false {
                UIView.animate(withDuration: 0.3) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
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
                                await CoreDataManager.shared.removeHistory(chapters: selectedChapters)
                                self.viewModel.removeHistory(for: selectedChapters)
                                self.reloadCells(for: selectedChapters)
                                self.updateReadButton()
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
                                let date = Date()
                                await CoreDataManager.shared.setCompleted(chapters: selectedChapters, date: date)
                                self.viewModel.addHistory(for: selectedChapters, date: date)
                                self.reloadCells(for: selectedChapters)
                                self.updateReadButton()
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

            toolbarItems = [
                markButton,
                UIBarButtonItem(systemItem: .flexibleSpace),
                downloadButton
            ]
        } else if !(self.navigationController?.isToolbarHidden ?? true) {
            // fade out toolbar
            UIView.animate(withDuration: 0.3) {
                self.navigationController?.toolbar.alpha = 0
            } completion: { _ in
                self.navigationController?.isToolbarHidden = true
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
                    DownloadManager.shared.download(chapters: [chapter], manga: self.manga)
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
                        await CoreDataManager.shared.setRead(
                            sourceId: chapter.sourceId,
                            mangaId: chapter.mangaId
                        )
                        await CoreDataManager.shared.setCompleted(
                            sourceId: chapter.sourceId,
                            mangaId: chapter.mangaId,
                            chapterId: chapter.id
                        )
                        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
                        await self.viewModel.loadHistory(manga: self.manga)
                        self.viewModel.readingHistory[chapter.id] = (-1, Int(Date().timeIntervalSince1970))
                        self.reloadCells(for: [chapter])
                        self.updateReadButton()
                    }
                })
            }
            if history.1 > 0 { // has read date
                actions.append(UIAction(
                    title: NSLocalizedString("MARK_UNREAD", comment: ""),
                    image: UIImage(systemName: "eye.slash")
                ) { _ in
                    Task {
                        await CoreDataManager.shared.removeHistory(
                            sourceId: chapter.sourceId,
                            mangaId: chapter.mangaId,
                            chapterId: chapter.id
                        )
                        NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
                        self.viewModel.readingHistory.removeValue(forKey: chapter.id)
                        self.reloadCells(for: [chapter])
                        self.updateReadButton()
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
                Task {
                    await CoreDataManager.shared.setRead(
                        sourceId: self.manga.sourceId,
                        mangaId: self.manga.id
                    )
                    let chapters = [Chapter](self.viewModel.chapterList[
                        indexPath.row..<self.viewModel.chapterList.count
                    ])
                    let date = Date()
                    await CoreDataManager.shared.setCompleted(chapters: chapters, date: date)
                    NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
                    self.viewModel.addHistory(for: chapters, date: date)
                    self.reloadCells(for: chapters)
                    self.updateReadButton()
                }
            },
            UIAction(
                title: NSLocalizedString("UNREAD", comment: ""),
                image: UIImage(systemName: "eye.slash")
            ) { _ in
                Task {
                    let chapters = [Chapter](self.viewModel.chapterList[
                        indexPath.row..<self.viewModel.chapterList.count
                    ])
                    await CoreDataManager.shared.removeHistory(chapters: chapters)
                    NotificationCenter.default.post(name: NSNotification.Name("updateHistory"), object: nil)
                    self.viewModel.removeHistory(for: chapters)
                    self.reloadCells(for: chapters)
                    self.updateReadButton()
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
        var chapters = chapters.filter { snapshot.itemIdentifiers.contains($0) } // filter out chapters not in data source
        if #available(iOS 15.0, *) {
            snapshot.reconfigureItems(chapters)
        } else {
            // swap chapters with chapters in data store (not doing this results in "invalid item identifier" crash)
            chapters = chapters.compactMap { chapter in
                snapshot.itemIdentifiers.first(where: { $0 == chapter })
            }
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
            let inLibrary = CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id)
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
        guard let url = manga.url else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    // open reader to next chapter
    func readPressed() {
        guard let chapter = headerView.nextChapter else { return }
        openReaderView(chapter: chapter)
    }
}

// MARK: - Chapter Sort Delegate
extension MangaViewController: ChapterSortDelegate {

    func sortOptionChanged(_ newOption: ChapterSortOption) {
        viewModel.sortChapters(method: newOption)
        refreshDataSource()
        updateReadButton()
    }

    func sortAscendingChanged(_ newValue: Bool) {
        viewModel.sortChapters(ascending: newValue)
        refreshDataSource()
        updateReadButton()
    }
}

// MARK: - Header Size Change Listener
extension MangaViewController: SizeChangeListenerDelegate {
    func sizeChanged(_ newSize: CGSize) {
        view.setNeedsLayout() // indirectly calls viewWillLayoutSubviews
    }
}

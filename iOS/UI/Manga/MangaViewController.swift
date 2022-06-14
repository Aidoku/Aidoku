//
//  MangaViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/30/22.
//

import UIKit
import SafariServices

class MangaViewController: UIViewController {

    var manga: Manga {
        didSet {
            (tableView.tableHeaderView as? MangaViewHeaderView)?.manga = manga
            view.setNeedsLayout()
        }
    }

    var chapters: [Chapter] {
        didSet {
            if !chapters.isEmpty {
                (tableView.tableHeaderView as? MangaViewHeaderView)?.headerTitle.text = "\(chapters.count) chapters"
            } else {
                (tableView.tableHeaderView as? MangaViewHeaderView)?.headerTitle.text = NSLocalizedString("NO_CHAPTERS", comment: "")
            }
            updateReadButton()
        }
    }
    var sortedChapters: [Chapter] {
        switch sortOption {
        case 0:
            return sortAscending ? chapters.reversed() : chapters
        case 1:
            return sortAscending ? orderedChapters.reversed() : orderedChapters
        default:
            return chapters
        }
    }
    var orderedChapters: [Chapter] {
        chapters.sorted { a, b in
            a.chapterNum ?? -1 < b.chapterNum ?? -1
        }
    }
    var readHistory: [String: (Int, Int)] = [:]

    var source: Source?

    var tintColor: UIColor? {
        didSet {
            setTintColor(tintColor)
        }
    }

    var sortOption: Int = 0 {
        didSet {
            tableView.reloadData()
        }
    }
    var sortAscending: Bool = false {
        didSet {
            tableView.reloadData()
        }
    }

    let tableView = UITableView(frame: .zero, style: .grouped)
    var hoveredIndexPath: IndexPath?
    var hovering = false

    let refreshControl = UIRefreshControl()

    var loadingAlert: UIAlertController?

    var observers: [NSObjectProtocol] = []

    init(manga: Manga, chapters: [Chapter] = []) {
        self.manga = manga
        self.chapters = chapters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = nil

        navigationItem.largeTitleDisplayMode = .never

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.delaysContentTouches = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        let headerView = MangaViewHeaderView(manga: manga)
        headerView.host = self
        if !chapters.isEmpty {
            headerView.headerTitle.text = "\(chapters.count) chapters"
        } else {
            headerView.headerTitle.text = NSLocalizedString("NO_CHAPTERS", comment: "")
        }
        headerView.safariButton.addTarget(self, action: #selector(openWebView), for: .touchUpInside)
        headerView.readButton.addTarget(self, action: #selector(readButtonPressed), for: .touchUpInside)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        tableView.tableHeaderView = headerView

        updateSortMenu()
        activateConstraints()

        getTintColor()

        source = SourceManager.shared.source(for: manga.sourceId)
        guard let source = source else {
            showMissingSourceWarning()
            return
        }

        let navbarUpdateBlock: (Notification) -> Void = { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateNavbarButtons()
            }
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateHistory"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateReadHistory()
                self.loadingAlert?.dismiss(animated: true)
                self.tableView.reloadData()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadFinished"), object: nil, queue: nil, using: navbarUpdateBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadRemoved"), object: nil, queue: nil, using: navbarUpdateBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadCancelled"), object: nil, queue: nil, using: navbarUpdateBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadsCancelled"), object: nil, queue: nil, using: navbarUpdateBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("downloadsRemoved"), object: nil, queue: nil, using: navbarUpdateBlock
        ))
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateLibrary"), object: nil, queue: nil, using: navbarUpdateBlock
        ))

        Task {
            if let newManga = try? await source.getMangaDetails(manga: manga) {
                manga = manga.copy(from: newManga)
                if chapters.isEmpty {
                    chapters = await DataManager.shared.getChapters(
                        for: manga,
                        fromSource: !DataManager.shared.libraryContains(manga: manga)
                    )
                    tableView.reloadSections(IndexSet(integer: 0), with: .fade)
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        becomeFirstResponder()

        updateNavbarButtons()
        updateReadHistory()
        tableView.reloadData()
        (tableView.tableHeaderView as? MangaViewHeaderView)?.updateViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setTintColor(tintColor)

        refreshControl.addTarget(self, action: #selector(refreshChapters), for: .valueChanged)
        if source != nil {
            tableView.refreshControl = refreshControl
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let header = tableView.tableHeaderView as? MangaViewHeaderView {
            header.contentStackView.layoutIfNeeded()
            header.frame.size.height = header.intrinsicContentSize.height
            tableView.tableHeaderView = header
        }
    }

    func activateConstraints() {
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        tableView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

//        editingToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
//        editingToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
//        editingToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        if let headerView = tableView.tableHeaderView as? MangaViewHeaderView {
            headerView.topAnchor.constraint(equalTo: tableView.topAnchor).isActive = true
            headerView.widthAnchor.constraint(equalTo: tableView.widthAnchor).isActive = true
            headerView.centerXAnchor.constraint(equalTo: tableView.centerXAnchor).isActive = true
            headerView.heightAnchor.constraint(equalTo: headerView.contentStackView.heightAnchor, constant: 10).isActive = true
        }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        updateNavbarButtons()
        updateToolbar()
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

            var subMenus: [UIMenu] = []

            // no longer needed because select chapters has a select all
//            let mangaOptions: [UIAction] = [
//                UIAction(title: NSLocalizedString("READ", comment: ""), image: nil) { _ in
//                    self.showLoadingIndicator()
//                    DataManager.shared.setRead(manga: self.manga)
//                    DataManager.shared.setCompleted(
//                        chapters: self.chapters,
//                        date: Date().addingTimeInterval(-1),
//                        context: DataManager.shared.backgroundContext
//                    )
//                    // Make most recent chapter appear as the most recently read
//                    if let firstChapter = self.chapters.first {
//                        DataManager.shared.setCompleted(chapter: firstChapter, context: DataManager.shared.backgroundContext)
//                    }
//                },
//                UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: nil) { _ in
//                    self.showLoadingIndicator()
//                    DataManager.shared.removeHistory(for: self.manga, context: DataManager.shared.backgroundContext)
//                }
//            ]
//            subMenus.append(UIMenu(title: NSLocalizedString("MARK_ALL", comment: ""), children: mangaOptions))

            var subActions: [UIAction] = []

            subActions.append(UIAction(
                title: NSLocalizedString("SELECT_CHAPTERS", comment: ""),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in
                self?.setEditing(true, animated: true)
            })

            if DataManager.shared.libraryContains(manga: manga), !DataManager.shared.getCategories().isEmpty {
                subActions.append(UIAction(
                    title: NSLocalizedString("EDIT_CATEGORIES", comment: ""),
                    image: UIImage(systemName: "folder")
                ) { [weak self] _ in
                    guard let self = self else { return }
                    self.present(UINavigationController(rootViewController: CategorySelectViewController(manga: self.manga)), animated: true)
                })
            }

            if DownloadManager.shared.hasDownloadedChapter(for: manga) {
                subActions.append(UIAction(
                    title: NSLocalizedString("REMOVE_ALL_DOWNLOADS", comment: ""),
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { [weak self] _ in
                    guard let self = self else { return }
                    DownloadManager.shared.deleteChapters(for: self.manga)
                })
            }

            subMenus.append(UIMenu(title: "", options: .displayInline, children: subActions))

            let menu = UIMenu(title: "", children: subMenus)

            Task { @MainActor in
                let moreButton = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: nil)
                moreButton.menu = menu
                navigationItem.rightBarButtonItem = moreButton
            }
        }
    }

    func updateToolbar() {
        if tableView.isEditing {
            if navigationController?.isToolbarHidden ?? true {
                UIView.animate(withDuration: 0.3) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
                }
            }

            let markButton = UIBarButtonItem(title: NSLocalizedString("MARK", comment: ""), style: .plain, target: self, action: nil)

            var downloadButton = UIBarButtonItem(
                title: NSLocalizedString("DOWNLOAD", comment: ""),
                style: .plain,
                target: self,
                action: #selector(downloadSelectedChapters)
            )

            let selectedRows = tableView.indexPathsForSelectedRows ?? []

            if !selectedRows.isEmpty {
                let chapters = selectedRows.count > 1 ? NSLocalizedString("CHAPTERS", comment: "") : NSLocalizedString("CHAPTER", comment: "")
                markButton.menu = UIMenu(
                    title: "\(selectedRows.count) \(chapters)",
                    children: [
                        UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: nil) { [weak self] _ in
                            guard let self = self else { return }
                            self.showLoadingIndicator()
                            DataManager.shared.removeHistory(
                                for: self.tableView.indexPathsForSelectedRows?.map { self.sortedChapters[$0.row] } ?? [],
                                context: DataManager.shared.backgroundContext
                            )
                            self.setEditing(false, animated: true)
                        },
                        UIAction(title: NSLocalizedString("READ", comment: ""), image: nil) { [weak self] _ in
                            guard let self = self else { return }
                            self.showLoadingIndicator()
                            let chapters = self.tableView.indexPathsForSelectedRows?.map { self.sortedChapters[$0.row] } ?? []
                            DataManager.shared.setCompleted(chapters: chapters, context: DataManager.shared.backgroundContext)
                            self.setEditing(false, animated: true)
                        }
                    ]
                )
                var allDownloaded = true
                for path in selectedRows where !DownloadManager.shared.isChapterDownloaded(chapter: sortedChapters[path.row]) {
                    allDownloaded = false
                    break
                }
                if allDownloaded {
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
            UIView.animate(withDuration: 0.3) {
                self.navigationController?.toolbar.alpha = 0
            } completion: { _ in
                self.navigationController?.isToolbarHidden = true
            }
        }
    }

    func showLoadingIndicator() {
        if loadingAlert == nil {
            loadingAlert = UIAlertController(title: nil, message: NSLocalizedString("LOADING_ELLIPSIS", comment: ""), preferredStyle: .alert)
            let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
            loadingIndicator.hidesWhenStopped = true
            loadingIndicator.style = .medium
            loadingIndicator.startAnimating()
            loadingAlert?.view.addSubview(loadingIndicator)
        }
        present(loadingAlert!, animated: true, completion: nil)
    }

    @objc func refreshChapters(refreshControl: UIRefreshControl) {
        guard let source = source else { return }
        Task { @MainActor in
            async let newManga = try? source.getMangaDetails(manga: manga)
            async let newChapters = DataManager.shared.getChapters(for: manga, fromSource: true)

            if let newManga = await newManga {
                manga = manga.copy(from: newManga)
            }
            chapters = await newChapters

            if DataManager.shared.libraryContains(manga: manga) {
                DataManager.shared.update(manga: manga, context: DataManager.shared.backgroundContext)
                DataManager.shared.set(chapters: chapters, for: manga)
                NotificationCenter.default.post(name: Notification.Name("updateLibrary"), object: nil)
            }
            tableView.reloadSections(IndexSet(integer: 0), with: .fade)
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
        guard let selected = tableView.indexPathsForSelectedRows else { return }
        // sort in reverse source order (oldest chapter to newest)
        let chapters = selected.map { self.sortedChapters[$0.row] }
            .filter { !DownloadManager.shared.isChapterDownloaded(chapter: $0) }
            .sorted { $0.sourceOrder > $1.sourceOrder }
        DownloadManager.shared.download(chapters: chapters, manga: manga)
        setEditing(false, animated: true)
    }

    @objc func deleteSelectedChapters() {
        guard let selected = tableView.indexPathsForSelectedRows else { return }

        let alertView = UIAlertController(
            title: NSLocalizedString("REMOVE_DOWNLOADS", comment: ""),
            message: NSLocalizedString("REMOVE_DOWNLOADS_CONFIRM", comment: ""),
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )
        alertView.addAction(UIAlertAction(title: NSLocalizedString("REMOVE", comment: ""), style: .destructive) { _ in
            DownloadManager.shared.delete(chapters: selected.map { self.sortedChapters[$0.row] })
            self.setEditing(false, animated: true)
        })
        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
        present(alertView, animated: true)

    }
}

extension MangaViewController {

    func setTintColor(_ color: UIColor?) {
        if let color = color {
            navigationController?.navigationBar.tintColor = color
            navigationController?.tabBarController?.tabBar.tintColor = color
            navigationController?.toolbar.tintColor = color
            view.tintColor = color
        } else {
            navigationController?.navigationBar.tintColor = UINavigationBar.appearance().tintColor
            navigationController?.tabBarController?.tabBar.tintColor = UITabBar.appearance().tintColor
//            view.tintColor = UIView().tintColor
        }
    }

    func getTintColor() {
        guard UserDefaults.standard.bool(forKey: "General.useMangaTint") else { return }
        if let tintColor = manga.tintColor?.color {
            // Adjust tint color for readability
            let luma = tintColor.luminance
            if luma >= 0.6 {
                self.tintColor = tintColor.darker(by: luma >= 0.9 ? 40 : 30)
            } else if luma <= 0.3 {
                self.tintColor = tintColor.lighter(by: luma <= 0.1 ? 30 : 20)
            } else {
                self.tintColor = tintColor
            }
        } else if let headerView = tableView.tableHeaderView as? MangaViewHeaderView {
            headerView.coverImageView.image?.getColors(quality: .low) { [weak self] colors in
                guard let self = self else { return }
                let luma = colors?.background.luminance ?? 0
                if luma >= 0.9 || luma <= 0.1, let secondary = colors?.secondary {
                    self.manga.tintColor = CodableColor(color: secondary)
                } else if let background = colors?.background {
                    self.manga.tintColor = CodableColor(color: background)
                } else {
                    self.manga.tintColor = nil
                }
                self.getTintColor()
            }
        }
    }

    func getNextChapter() -> Chapter? {
        let id = readHistory.max { a, b in a.value.1 < b.value.1 }?.key
        if let id = id {
            return chapters.first { $0.id == id }
        }
        return chapters.last
    }

    func updateSortMenu() {
        guard tableView.tableHeaderView != nil else { return }
        let sortOptions: [UIAction] = [
            UIAction(
                title: NSLocalizedString("SOURCE_ORDER", comment: ""),
                image: sortOption == 0 ? UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down") : nil
            ) { [weak self] _ in
                guard let self = self else { return }
                if self.sortOption == 0 {
                    self.sortAscending.toggle()
                } else {
                    self.sortAscending = false
                    self.sortOption = 0
                }
                self.updateSortMenu()
            },
            UIAction(
                title: NSLocalizedString("CHAPTER", comment: ""),
                image: sortOption == 1 ? UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down") : nil
            ) { [weak self] _ in
                guard let self = self else { return }
                if self.sortOption == 1 {
                    self.sortAscending.toggle()
                } else {
                    self.sortAscending = false
                    self.sortOption = 1
                }
                self.updateSortMenu()
            }
        ]
        let menu = UIMenu(title: "", image: nil, identifier: nil, options: [], children: sortOptions)
        (tableView.tableHeaderView as? MangaViewHeaderView)?.sortButton.showsMenuAsPrimaryAction = true
        (tableView.tableHeaderView as? MangaViewHeaderView)?.sortButton.menu = menu
    }

    func updateReadButton() {
        var titleString = ""
        if SourceManager.shared.source(for: manga.sourceId) == nil {
            titleString = NSLocalizedString("UNAVAILABLE", comment: "")
        } else if let chapter = getNextChapter() {
            if readHistory[chapter.id]?.1 ?? 0 == 0 {
                titleString.append(NSLocalizedString("START_READING", comment: ""))
            } else {
                titleString.append(NSLocalizedString("CONTINUE_READING", comment: ""))
            }
            if let volumeNum = chapter.volumeNum {
                titleString.append(String(format: " \(NSLocalizedString("VOL_X", comment: ""))", volumeNum))
            }
            if let chapterNum = chapter.chapterNum {
                titleString.append(String(format: " \(NSLocalizedString("CH_X", comment: ""))", chapterNum))
            }
        } else {
            titleString = NSLocalizedString("NO_CHAPTERS_AVAILABLE", comment: "")
        }
        (tableView.tableHeaderView as? MangaViewHeaderView)?.readButton.setTitle(titleString, for: .normal)
    }

    func updateReadHistory() {
        readHistory = DataManager.shared.getReadHistory(manga: manga)
        updateReadButton()
    }

    func openReaderView(for chapter: Chapter) {
        let readerController = ReaderViewController(manga: manga, chapter: chapter, chapterList: chapters)
        let navigationController = ReaderNavigationController(rootViewController: readerController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    func showMissingSourceWarning() {
        let alert = UIAlertController(
            title: NSLocalizedString("MISSING_SOURCE", comment: ""),
            message: NSLocalizedString("MISSING_SOURCE_TEXT", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
        self.present(alert, animated: true, completion: nil)
    }

    @objc func readButtonPressed() {
        if let chapter = getNextChapter(), SourceManager.shared.source(for: manga.sourceId) != nil {
            openReaderView(for: chapter)
        }
    }

    @objc func openWebView() {
        if let url = URL(string: manga.url ?? "") {
            let config = SFSafariViewController.Configuration()
            config.entersReaderIfAvailable = true

            let vc = SFSafariViewController(url: url, configuration: config)
            present(vc, animated: true)
        }
    }
}

// MARK: - Table View Data Source
extension MangaViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chapters.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let history = readHistory[sortedChapters[indexPath.row].id]
        return MangaChapterTableViewCell(
            chapter: sortedChapters[indexPath.row],
            completed: history?.0 ?? 0 == -1,
            page: history?.0 ?? 0,
            reuseIdentifier: "ChapterTableViewCell"
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ -> UIMenu? in
            guard let self = self else { return nil }
            var actions: [UIMenuElement] = []
            // download action
            let downloadAction: UIMenuElement
            let downloadStatus = DownloadManager.shared.getDownloadStatus(for: self.sortedChapters[indexPath.row])
            if downloadStatus == .finished {
                downloadAction = UIAction(
                    title: NSLocalizedString("REMOVE_DOWNLOAD", comment: ""),
                    image: nil, attributes: .destructive
                ) { [weak self] _ in
                    guard let self = self else { return }
                    DownloadManager.shared.delete(chapters: [self.sortedChapters[indexPath.row]])
                }
            } else if downloadStatus == .downloading {
                downloadAction = UIAction(
                    title: NSLocalizedString("CANCEL_DOWNLOAD", comment: ""),
                    image: nil, attributes: .destructive
                ) { [weak self] _ in
                    guard let self = self else { return }
                    DownloadManager.shared.cancelDownload(for: self.sortedChapters[indexPath.row])
                }
            } else {
                downloadAction = UIAction(title: NSLocalizedString("DOWNLOAD", comment: ""), image: nil) { [weak self] _ in
                    guard let self = self else { return }
                    DownloadManager.shared.download(chapters: [self.sortedChapters[indexPath.row]], manga: self.manga)
                }
            }
            actions.append(UIMenu(title: "", options: .displayInline, children: [downloadAction]))
            // marking actions
            let history = self.readHistory[self.sortedChapters[indexPath.row].id] ?? (0, 0)
            if history.1 <= 0 || history.0 > 0 {
                actions.append(UIAction(title: NSLocalizedString("MARK_READ", comment: ""), image: nil) { [weak self] _ in
                    guard let self = self else { return }
                    DataManager.shared.setRead(manga: self.manga)
                    DataManager.shared.setCompleted(chapter: self.sortedChapters[indexPath.row])
                    self.updateReadHistory()
                    tableView.reloadData()
                })
            }
            if history.1 > 0 {
                actions.append(UIAction(title: NSLocalizedString("MARK_UNREAD", comment: ""), image: nil) { [weak self] _ in
                    guard let self = self else { return }
                    DataManager.shared.removeHistory(for: self.sortedChapters[indexPath.row])
                    self.updateReadHistory()
                    tableView.reloadData()
                })
            }
            if indexPath.row != self.chapters.count - 1 {
                let previousSubmenu = UIMenu(title: NSLocalizedString("MARK_PREVIOUS", comment: ""), children: [
                    UIAction(title: NSLocalizedString("READ", comment: ""), image: nil) { [weak self] _ in
                        guard let self = self else { return }
                        DataManager.shared.setRead(manga: self.manga)
                        DataManager.shared.setCompleted(
                            chapters: [Chapter](self.sortedChapters[indexPath.row + 1 ..< self.sortedChapters.count]),
                            date: Date().addingTimeInterval(-1)
                        )
                        DataManager.shared.setCompleted(chapter: self.sortedChapters[indexPath.row])
                        self.updateReadHistory()
                        tableView.reloadData()
                    },
                    UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: nil) { [weak self] _ in
                        guard let self = self else { return }
                        DataManager.shared.removeHistory(for: [Chapter](self.sortedChapters[indexPath.row ..< self.sortedChapters.count]))
                        self.updateReadHistory()
                        tableView.reloadData()
                    }
                ])
                actions.append(previousSubmenu)
            }
            return UIMenu(title: "", children: actions)
        }
    }
}

// MARK: - Table View Delegate
extension MangaViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !tableView.isEditing { // open reader view
            tableView.deselectRow(at: indexPath, animated: true)

            if SourceManager.shared.source(for: manga.sourceId) != nil {
                openReaderView(for: sortedChapters[indexPath.row])
            }
        } else {
            updateToolbar()
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateToolbar()
        }
    }

    func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }
}

// MARK: - Key Handler
extension MangaViewController {
    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: "Select Previous Item in List",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Select Next Item in List",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Confirm Selection",
                action: #selector(enterKeyPressed),
                input: "\r",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Clear Selection",
                action: #selector(escKeyPressed),
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            )
        ]
    }

    @objc func arrowKeyPressed(_ sender: UIKeyCommand) {
        if !hovering {
            hovering = true
            if hoveredIndexPath == nil { hoveredIndexPath = IndexPath(row: 0, section: 0) }
            tableView.cellForRow(at: hoveredIndexPath!)?.setHighlighted(true, animated: true)
            return
        }
        guard let hoveredIndexPath = hoveredIndexPath else { return }
        var position = hoveredIndexPath.row
        var section = hoveredIndexPath.section
        switch sender.input {
        case UIKeyCommand.inputUpArrow: position -= 1
        case UIKeyCommand.inputDownArrow: position += 1
        default: return
        }
        if position < 0 {
            guard section > 0 else { return }
            section -= 1
            position = tableView.numberOfRows(inSection: section) - 1
        } else if position >= tableView.numberOfRows(inSection: section) {
            guard section < tableView.numberOfSections - 1 else { return }
            section += 1
            position = 0
        }
        let newHoveredIndexPath = IndexPath(row: position, section: section)
        tableView.cellForRow(at: hoveredIndexPath)?.setHighlighted(false, animated: true)
        tableView.cellForRow(at: newHoveredIndexPath)?.setHighlighted(true, animated: true)
        tableView.scrollToRow(at: newHoveredIndexPath, at: .middle, animated: true)
        self.hoveredIndexPath = newHoveredIndexPath
    }

    @objc func enterKeyPressed() {
        guard !tableView.isEditing, hovering, let hoveredIndexPath = hoveredIndexPath else { return }
        tableView(tableView, didSelectRowAt: hoveredIndexPath)
    }

    @objc func escKeyPressed() {
        guard !tableView.isEditing, hovering, let hoveredIndexPath = hoveredIndexPath else { return }
        tableView.cellForRow(at: hoveredIndexPath)?.setHighlighted(false, animated: true)
        hovering = false
        self.hoveredIndexPath = nil
    }
}

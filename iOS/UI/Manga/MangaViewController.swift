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
    var readHistory: [String: Int] = [:]

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
    let refreshControl = UIRefreshControl()

    var loadingAlert: UIAlertController?

    init(manga: Manga, chapters: [Chapter] = []) {
        self.manga = manga
        self.chapters = chapters
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = nil

        navigationItem.largeTitleDisplayMode = .never

        updateNavbarButtons()

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
        updateReadHistory()
        activateConstraints()

        getTintColor()

        source = SourceManager.shared.source(for: manga.sourceId)
        guard let source = source else {
            showMissingSourceWarning()
            return
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("updateHistory"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.updateReadHistory()
                self.loadingAlert?.dismiss(animated: true)
                self.tableView.reloadData()
            }
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("downloadFinished"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.updateNavbarButtons()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("downloadRemoved"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.updateNavbarButtons()
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("downloadsRemoved"), object: nil, queue: nil) { _ in
            Task { @MainActor in
                self.updateNavbarButtons()
            }
        }

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

            // TODO: only show relevant actions
            let mangaOptions: [UIAction] = [
                UIAction(title: NSLocalizedString("READ", comment: ""), image: nil) { _ in
                    self.showLoadingIndicator()
                    DataManager.shared.setRead(manga: self.manga)
                    DataManager.shared.setCompleted(
                        chapters: self.chapters,
                        date: Date().addingTimeInterval(-1),
                        context: DataManager.shared.backgroundContext
                    )
                    // Make most recent chapter appear as the most recently read
                    if let firstChapter = self.chapters.first {
                        DataManager.shared.setCompleted(chapter: firstChapter, context: DataManager.shared.backgroundContext)
                    }
                },
                UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: nil) { _ in
                    self.showLoadingIndicator()
                    DataManager.shared.removeHistory(for: self.manga, context: DataManager.shared.backgroundContext)
                }
            ]
            subMenus.append(UIMenu(title: NSLocalizedString("MARK_ALL", comment: ""), children: mangaOptions))

            var subActions: [UIAction] = []

            subActions.append(UIAction(title: NSLocalizedString("SELECT_CHAPTERS", comment: ""), image: nil) { _ in
                self.setEditing(true, animated: true)
            })

            if DownloadManager.shared.hasDownloadedChapter(for: manga) {
                subActions.append(UIAction(title: NSLocalizedString("REMOVE_ALL_DOWNLOADS", comment: ""), image: nil) { _ in
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
            if self.navigationController?.isToolbarHidden ?? true {
                UIView.animate(withDuration: 0.3) {
                    self.navigationController?.isToolbarHidden = false
                    self.navigationController?.toolbar.alpha = 1
                }
            }

            let markButton = UIBarButtonItem(title: NSLocalizedString("MARK", comment: ""), style: .plain, target: self, action: nil)
            let downloadButton = UIBarButtonItem(
                title: NSLocalizedString("DOWNLOAD", comment: ""),
                style: .plain,
                target: self,
                action: #selector(downloadSelectedChapters)
            )

            let selectedRowCount = tableView.indexPathsForSelectedRows?.count ?? 0

            if selectedRowCount > 0 {
                let chapters = selectedRowCount > 1 ? NSLocalizedString("CHAPTERS", comment: "") : NSLocalizedString("CHAPTER", comment: "")
                markButton.menu = UIMenu(
                    title: "\(selectedRowCount) \(chapters)",
                    children: [
                        UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: nil) { _ in
                            self.showLoadingIndicator()
                            DataManager.shared.removeHistory(
                                for: self.tableView.indexPathsForSelectedRows?.map { self.sortedChapters[$0.row] } ?? [],
                                context: DataManager.shared.backgroundContext
                            )
                            self.setEditing(false, animated: true)
                        },
                        UIAction(title: NSLocalizedString("READ", comment: ""), image: nil) { _ in
                            self.showLoadingIndicator()
                            let chapters = self.tableView.indexPathsForSelectedRows?.map { self.sortedChapters[$0.row] } ?? []
                            DataManager.shared.addHistory(for: chapters, context: DataManager.shared.backgroundContext)
                            self.setEditing(false, animated: true)
                        }
                    ]
                )
            }

            markButton.isEnabled = selectedRowCount > 0
            downloadButton.isEnabled = selectedRowCount > 0

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
            loadingAlert = UIAlertController(title: nil, message: "Loading...", preferredStyle: .alert)
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
        DownloadManager.shared.download(chapters: selected.map { self.sortedChapters[$0.row] }.reversed(), manga: manga)
        setEditing(false, animated: true)
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
            headerView.coverImageView.image?.getColors(quality: .low) { colors in
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
        let id = readHistory.max { a, b in a.value < b.value }?.key
        if let id = id {
            return chapters.first { $0.id == id }
        }
        return chapters.last
    }

    func updateSortMenu() {
        if let headerView = tableView.tableHeaderView as? MangaViewHeaderView {
            let sortOptions: [UIAction] = [
                UIAction(title: NSLocalizedString("SOURCE_ORDER", comment: ""),
                         image: sortOption == 0 ? UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down") : nil) { _ in
                    if self.sortOption == 0 {
                        self.sortAscending.toggle()
                    } else {
                        self.sortAscending = false
                        self.sortOption = 0
                    }
                    self.updateSortMenu()
                },
                UIAction(title: NSLocalizedString("CHAPTER", comment: ""),
                         image: sortOption == 1 ? UIImage(systemName: sortAscending ? "chevron.up" : "chevron.down") : nil) { _ in
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
            headerView.sortButton.showsMenuAsPrimaryAction = true
            headerView.sortButton.menu = menu
        }
    }

    func updateReadButton(_ headerView: MangaViewHeaderView? = nil) {
        var titleString = ""
        if SourceManager.shared.source(for: manga.sourceId) == nil {
            titleString = NSLocalizedString("UNAVAILABLE", comment: "")
        } else if let chapter = getNextChapter() {
            if readHistory[chapter.id] ?? 0 == 0 {
                titleString.append(NSLocalizedString("START_READING", comment: ""))
            } else {
                titleString.append(NSLocalizedString("CONTINUE_READING", comment: ""))
            }
            if let volumeNum = chapter.volumeNum {
                titleString.append(String(format: " Vol.%g", volumeNum))
            }
            if let chapterNum = chapter.chapterNum {
                titleString.append(String(format: " Ch.%g", chapterNum))
            }
        } else {
            titleString = NSLocalizedString("NO_CHAPTERS_AVAILABLE", comment: "")
        }
        if let headerView = headerView {
            headerView.readButton.setTitle(titleString, for: .normal)
        } else {
            (tableView.tableHeaderView as? MangaViewHeaderView)?.readButton.setTitle(titleString, for: .normal)
        }
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
            title: NSLocalizedString("MANGA_MISSING_SOURCE", comment: ""),
            message: NSLocalizedString("MANGA_MISSING_SOURCE_TEXT", comment: ""),
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
        MangaChapterTableViewCell(
            chapter: sortedChapters[indexPath.row],
            read: readHistory[sortedChapters[indexPath.row].id] ?? 0 > 0,
            reuseIdentifier: "ChapterTableViewCell"
        )
    }

    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            var actions: [UIMenuElement] = []
            // download action
            let downloadAction: UIMenuElement
            let downloadStatus = DownloadManager.shared.getDownloadStatus(for: self.sortedChapters[indexPath.row])
            if downloadStatus == .finished {
                downloadAction = UIAction(title: NSLocalizedString("REMOVE_DOWNLOAD", comment: ""), image: nil, attributes: .destructive) { _ in
                    DownloadManager.shared.delete(chapters: [self.sortedChapters[indexPath.row]])
                }
            } else if downloadStatus == .downloading {
                downloadAction = UIAction(title: NSLocalizedString("CANCEL_DOWNLOAD", comment: ""), image: nil, attributes: .destructive) { _ in
                    DownloadManager.shared.cancelDownload(for: self.sortedChapters[indexPath.row])
                }
            } else {
                downloadAction = UIAction(title: NSLocalizedString("DOWNLOAD", comment: ""), image: nil) { _ in
                    DownloadManager.shared.download(chapters: [self.sortedChapters[indexPath.row]], manga: self.manga)
                }
            }
            actions.append(UIMenu(title: "", options: .displayInline, children: [downloadAction]))
            // marking actions
            let action: UIAction
            if self.readHistory[self.sortedChapters[indexPath.row].id] ?? 0 > 0 {
                action = UIAction(title: NSLocalizedString("MARK_UNREAD", comment: ""), image: nil) { _ in
                    DataManager.shared.removeHistory(for: self.sortedChapters[indexPath.row])
                    self.updateReadHistory()
                    tableView.reloadData()
                }
            } else {
                action = UIAction(title: NSLocalizedString("MARK_READ", comment: ""), image: nil) { _ in
                    DataManager.shared.setRead(manga: self.manga)
                    DataManager.shared.addHistory(for: self.sortedChapters[indexPath.row])
                    self.updateReadHistory()
                    tableView.reloadData()
                }
            }
            actions.append(action)
            if indexPath.row != self.chapters.count - 1 {
                let previousSubmenu = UIMenu(title: NSLocalizedString("MARK_PREVIOUS", comment: ""), children: [
                    UIAction(title: NSLocalizedString("READ", comment: ""), image: nil) { _ in
                        DataManager.shared.setRead(manga: self.manga)
                        DataManager.shared.setCompleted(
                            chapters: [Chapter](self.sortedChapters[indexPath.row + 1 ..< self.sortedChapters.count]),
                            date: Date().addingTimeInterval(-1)
                        )
                        DataManager.shared.setCompleted(chapter: self.sortedChapters[indexPath.row])
                        self.updateReadHistory()
                        tableView.reloadData()
                    },
                    UIAction(title: NSLocalizedString("UNREAD", comment: ""), image: nil) { _ in
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
}

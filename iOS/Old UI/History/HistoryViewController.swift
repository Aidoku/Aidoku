//
//  HistoryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/2/22.
//

import UIKit
import LocalAuthentication

struct HistoryEntry {
    var manga: Manga
    var chapter: Chapter
    var date: Date
    var currentPage: Int?
    var totalPages: Int?
}

class HistoryViewController: UIViewController {

    let tableView = UITableView(frame: .zero, style: .grouped)

    var hoveredIndexPath: IndexPath?
    var hovering = false

    // (days ago, entries)
    var entries: [(Int, [HistoryEntry])] = [] {
        didSet {
            filterSearchEntries()
        }
    }
    var filteredSearchEntries: [(Int, [HistoryEntry])] = []
    var shownMangaKeys: [String] = []

    var offset = 0
    var loadingMore = false {
        didSet {
            Task { @MainActor in
                tableView.tableFooterView?.isHidden = !loadingMore
            }
        }
    }
    var loadingTask: Task<(), Never>?
    var reachedEnd = false
    var queueRefresh = false

    var searchText = ""
    var locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab") {
        didSet {
            updateNavbarItems()
            updateLockState()
        }
    }

    let lockedView = UIStackView()
    let lockedImageView = UIImageView()
    let lockedText = UILabel()
    let lockedButton = UIButton(type: .roundedRect)

    var observers: [Any] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("HISTORY", comment: "")
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.delaysContentTouches = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(HistoryTableViewCell.self, forCellReuseIdentifier: "HistoryTableViewCell")
        tableView.register(SourceSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: "SourceSectionHeaderView")
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        view.addSubview(tableView)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        tableView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 20)
        tableView.tableFooterView = spinner
        tableView.tableFooterView?.isHidden = true

        lockedView.distribution = .fill
        lockedView.spacing = 12
        lockedView.alignment = .center
        lockedView.axis = .vertical
        lockedView.translatesAutoresizingMaskIntoConstraints = false
        lockedView.isHidden = true
        view.addSubview(lockedView)

        lockedImageView.image = UIImage(systemName: "lock.fill")
        lockedImageView.contentMode = .scaleAspectFit
        lockedImageView.tintColor = .secondaryLabel
        lockedImageView.translatesAutoresizingMaskIntoConstraints = false
        lockedView.addArrangedSubview(lockedImageView)

        lockedText.text = NSLocalizedString("HISTORY_LOCKED", comment: "")
        lockedText.font = .systemFont(ofSize: 16, weight: .medium)
        lockedView.addArrangedSubview(lockedText)
        lockedView.setCustomSpacing(2, after: lockedText)

        lockedButton.setTitle(NSLocalizedString("VIEW_HISTORY", comment: ""), for: .normal)
        lockedButton.addTarget(self, action: #selector(unlock), for: .touchUpInside)
        lockedView.addArrangedSubview(lockedButton)

        lockedImageView.heightAnchor.constraint(equalToConstant: 66).isActive = true
        lockedImageView.widthAnchor.constraint(equalToConstant: 66).isActive = true
        lockedView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        lockedView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        let unlockTap = UITapGestureRecognizer(target: self, action: #selector(unlock))
        lockedView.addGestureRecognizer(unlockTap)

        locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        fetchNewEntries()

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateHistory"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.queueRefresh = true
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("historyAdded"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.queueRefresh = true
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("historyRemoved"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.queueRefresh = true
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("historySet"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.queueRefresh = true
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("History.lockHistoryTab"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        })
        // lock when app moves to background
        observers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        becomeFirstResponder()

        if queueRefresh {
            queueRefresh = false
            reloadHistory()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func updateNavbarItems() {
        let clearButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearAllHistory)
        )
        if UserDefaults.standard.bool(forKey: "History.lockHistoryTab") {
            let lockButton: UIBarButtonItem
            if locked {
                lockButton = UIBarButtonItem(
                    image: UIImage(systemName: "lock"),
                    style: .plain,
                    target: self,
                    action: #selector(unlock)
                )
                clearButton.isEnabled = false
            } else {
                lockButton = UIBarButtonItem(
                    image: UIImage(systemName: "lock.open"),
                    style: .plain,
                    target: self,
                    action: #selector(lock)
                )
            }
            navigationItem.rightBarButtonItems = [clearButton, lockButton]
        } else {
            navigationItem.rightBarButtonItems = [clearButton]
        }
    }

    func updateLockState() {
        if locked {
            self.tableView.isHidden = true
            self.lockedView.isHidden = false
            self.tableView.alpha = 0
            self.lockedView.alpha = 1
        } else {
            self.tableView.isHidden = false
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.lockedView.alpha = 0
            } completion: { _ in
                self.lockedView.isHidden = true
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                    self.tableView.alpha = 1
                }
            }
        }
    }

    func reloadHistory() {
        if loadingMore {
            loadingTask?.cancel()
            loadingTask = nil
            loadingMore = false
        }
        entries = []
        filteredSearchEntries = []
        shownMangaKeys = []
        offset = 0
        reachedEnd = false
        Task { @MainActor in
            tableView.reloadData()
            fetchNewEntries()
        }
    }

    struct HistoryInfo {
        let sourceId: String
        let mangaId: String
        let chapterId: String
        let dateRead: Date?
        let progress: Int16
        let total: Int16
        let completed: Bool
    }

    // swiftlint:disable:next cyclomatic_complexity
    func fetchNewEntries() {
        guard !loadingMore, !reachedEnd else { return }
        loadingMore = true
        let entries = entries
        let offset = offset
        loadingTask = Task {
            var historyDict: [Int: [HistoryEntry]] = entries.reduce(into: [:]) { $0[$1.0] = $1.1 }
            var mangaKeys: [String] = self.shownMangaKeys
            let historyObj = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.getRecentHistory(limit: 15, offset: offset, context: context).map {
                    HistoryInfo(
                        sourceId: $0.sourceId,
                        mangaId: $0.mangaId,
                        chapterId: $0.chapterId,
                        dateRead: $0.dateRead,
                        progress: $0.progress,
                        total: $0.total,
                        completed: $0.completed
                    )
                }
            }
            // all history is displayed
            if historyObj.isEmpty {
                self.reachedEnd = true
                self.loadingMore = false
                return
            }
            for obj in historyObj {
                let days = Calendar.autoupdatingCurrent.dateComponents(
                    Set([Calendar.Component.day]),
                    from: obj.dateRead ?? Date.distantPast,
                    to: Date()
                ).day ?? 0
                var arr = historyDict[days] ?? []

                let key = "\(obj.sourceId).\(obj.mangaId)"

                guard !mangaKeys.contains(key) else { continue }

                var (manga, chapter) = await CoreDataManager.shared.container.performBackgroundTask { context in
                    (
                        CoreDataManager.shared.getManga(
                            sourceId: obj.sourceId,
                            mangaId: obj.mangaId,
                            context: context
                        )?.toManga(),
                        CoreDataManager.shared.getChapter(
                            sourceId: obj.sourceId,
                            mangaId: obj.mangaId,
                            chapterId: obj.chapterId,
                            context: context
                        )?.toChapter()
                    )
                }
                if manga == nil || chapter == nil {
                    let source = SourceManager.shared.source(for: obj.sourceId)
                    let tempManga = Manga(sourceId: obj.sourceId, id: obj.mangaId)
                    if manga == nil {
                        manga = try? await source?.getMangaDetails(manga: tempManga)
                    }
                    if chapter == nil {
                        chapter = (try? await source?.getChapterList(manga: tempManga))?.first { $0.id == obj.chapterId }
                    }
                }
                guard let manga = manga, let chapter = chapter else { continue }

                mangaKeys.append(key)

                let new = HistoryEntry(
                    manga: manga,
                    chapter: chapter,
                    date: obj.dateRead ?? Date.distantPast,
                    currentPage: obj.completed ? -1 : Int(obj.progress),
                    totalPages: Int(obj.total)
                )
                arr.append(new)
                historyDict[days] = arr
            }
            let finalMangaKeys = mangaKeys
            let finalHistoryDict = historyDict
            Task { @MainActor in
                self.shownMangaKeys = finalMangaKeys
                self.entries = finalHistoryDict.map { ($0.key, $0.value) }.sorted { $0.0 < $1.0 }
                self.offset += 15
                if entries.isEmpty || self.entries.count < entries.count || self.tableView.numberOfSections == 0 {
                    self.tableView.reloadData()
                } else {
                    self.tableView.performBatchUpdates {
                        if self.entries.count > entries.count {
                            self.tableView.insertSections(IndexSet(integersIn: entries.count..<self.entries.count), with: .fade)
                        }
                        if !entries.isEmpty {
                            let previousRow = entries.count - 1
                            if self.entries[previousRow].1.count != entries[previousRow].1.count {
                                self.tableView.insertRows(
                                    at: (entries[previousRow].1.count..<self.entries[previousRow].1.count).map {
                                        IndexPath(row: $0, section: previousRow)
                                    },
                                    with: .fade
                                )
                            }
                        }
                    }
                }
                self.loadingMore = false
                // last cell visible
                if self.tableView.indexPathsForVisibleRows?.contains(
                    IndexPath(row: (self.entries.last?.1.count ?? 1) - 1, section: self.entries.count - 1)
                ) ?? false {
                    self.fetchNewEntries()
                }
            }
        }
    }

    func filterSearchEntries() {
        guard !searchText.isEmpty else {
            filteredSearchEntries = entries
            return
        }
        let searchString = searchText.lowercased()
        var entries = entries
        var i = 0
        for section in entries {
            entries[i] = (section.0, section.1.filter {
                $0.manga.title?.lowercased().fuzzyMatch(searchString) ?? false ||
                $0.manga.author?.lowercased().fuzzyMatch(searchString) ?? false
            })
            if entries[i].1.isEmpty {
                entries.remove(at: i)
                i -= 1
            }
            i += 1
        }
        filteredSearchEntries = entries
    }

    @objc func clearAllHistory() {
        let alertView = UIAlertController(
            title: NSLocalizedString("CLEAR_READ_HISTORY", comment: ""),
            message: NSLocalizedString("CLEAR_READ_HISTORY_TEXT", comment: ""),
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )

        let action = UIAlertAction(title: NSLocalizedString("CLEAR", comment: ""), style: .destructive) { _ in
            Task { @MainActor in
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.clearHistory(context: context)
                    try? context.save()
                }
                self.reloadHistory()
            }
        }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
        present(alertView, animated: true)
    }

    @objc func unlock() {
        let context = LAContext()

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            let reason = NSLocalizedString("AUTH_FOR_HISTORY", comment: "")

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
                guard let self = self else { return }
                Task { @MainActor in
                    if success {
                        self.locked = false
                    }
                }
            }
        } else { // biometrics not supported
            locked = false
        }
    }

    @objc func lock() {
        locked = true
    }
}

// MARK: - Table View Data Source
extension HistoryViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        filteredSearchEntries.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredSearchEntries[section].1.count
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        20
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        12
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SourceSectionHeaderView") as? SourceSectionHeaderView
        view?.title.text = self.tableView(tableView, titleForHeaderInSection: section)
        return view
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section < filteredSearchEntries.count else { return nil }
        let days = filteredSearchEntries[section].0
        return Date.makeRelativeDate(days: days)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "HistoryTableViewCell", for: indexPath) as? HistoryTableViewCell
        if cell == nil {
            cell = HistoryTableViewCell(reuseIdentifier: "HistoryTableViewCell")
        }
        guard let cell = cell else { return UITableViewCell() }
        guard indexPath.section < filteredSearchEntries.count,
              indexPath.row < filteredSearchEntries[indexPath.section].1.count else {
            return cell
        }
        cell.entry = filteredSearchEntries[indexPath.section].1[indexPath.row]
        return cell
    }
}

// MARK: - Table View Delegate
extension HistoryViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.section].1[indexPath.row]
        navigationController?.pushViewController(
            MangaViewController(manga: entry.manga),
            animated: true
        )
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard searchText.isEmpty else { return } // disable load more while searching
        if indexPath.section == entries.count - 1 && indexPath.row == (entries.last?.1.count ?? 1) - 1 {
            fetchNewEntries()
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .normal, title: NSLocalizedString("DELETE", comment: "")) { _, _, completion in
            let entry = self.filteredSearchEntries[indexPath.section].1[indexPath.row]

            let alertView = UIAlertController(
                title: NSLocalizedString("CLEAR_READ_HISTORY", comment: ""),
                message: NSLocalizedString("REMOVE_CHAPTER_HISTORY_TEXT", comment: ""),
                preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
            )

            alertView.addAction(UIAlertAction(title: NSLocalizedString("REMOVE", comment: ""), style: .destructive) { _ in
                Task {
                    await HistoryManager.shared.removeHistory(chapters: [entry.chapter])
                    self.reloadHistory()
                    completion(true)
                }
            })
            alertView.addAction(UIAlertAction(title: NSLocalizedString("REMOVE_ALL_MANGA_HISTORY", comment: ""), style: .destructive) { _ in
                Task {
                    await HistoryManager.shared.removeHistory(manga: entry.manga)
                    self.reloadHistory()
                    completion(true)
                }
            })
            alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel) { _ in
                completion(false)
            })

            self.present(alertView, animated: true)
        }
        delete.backgroundColor = .red

        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - Search Results Updater
extension HistoryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        filterSearchEntries()
        tableView.reloadData()
    }
}

// MARK: - Key Handler
extension HistoryViewController {
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

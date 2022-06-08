//
//  HistoryViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/2/22.
//

import UIKit

struct HistoryEntry {
    var manga: Manga
    var chapter: Chapter
    var date: Date
}

class HistoryViewController: UITableViewController {

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
            tableView.tableFooterView?.isHidden = !loadingMore
        }
    }
    var reachedEnd = false

    var searchText = ""

    var observers: [Any] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("HISTORY", comment: "")
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(clearAllHistory)
        )

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.register(HistoryTableViewCell.self, forCellReuseIdentifier: "HistoryTableViewCell")
        tableView.register(SourceSectionHeaderView.self, forHeaderFooterViewReuseIdentifier: "SourceSectionHeaderView")
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground

        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 20)
        tableView.tableFooterView = spinner
        tableView.tableFooterView?.isHidden = true

        fetchNewEntries()

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateHistory"), object: nil, queue: nil
        ) { [weak self] _ in
            self?.reloadHistory()
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }

    func reloadHistory() {
        entries = []
        filteredSearchEntries = []
        shownMangaKeys = []
        offset = 0
        reachedEnd = false
        tableView.reloadData()
        fetchNewEntries()
    }

    func fetchNewEntries() {
        guard !loadingMore, !reachedEnd else { return }
        loadingMore = true
        let entries = entries
        let offset = offset
        Task.detached {
            var historyDict: [Int: [HistoryEntry]] = entries.reduce(into: [:]) { $0[$1.0] = $1.1 }
            let historyObj = (try? DataManager.shared.getReadHistory(limit: 15, offset: offset)) ?? []
            if historyObj.isEmpty {
                Task { @MainActor in
                    self.reachedEnd = true
                    self.loadingMore = false
                }
                return
            }
            var mangaKeys: [String] = await self.shownMangaKeys
            for obj in historyObj {
                let days = Calendar.autoupdatingCurrent.dateComponents(Set([Calendar.Component.day]), from: obj.dateRead, to: Date()).day ?? 0
                var arr = historyDict[days] ?? []

                let key = "\(obj.sourceId).\(obj.mangaId)"

                guard !mangaKeys.contains(key),
                      let manga = await DataManager.shared.getManga(sourceId: obj.sourceId, mangaId: obj.mangaId),
                      let chapter = await DataManager.shared.getChapter(sourceId: obj.sourceId, mangaId: obj.mangaId, chapterId: obj.chapterId) else {
                    continue
                }

                mangaKeys.append(key)

                let new = HistoryEntry(
                    manga: manga,
                    chapter: chapter,
                    date: obj.dateRead
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
            entries[i] = (section.0, section.1.filter { $0.manga.title?.lowercased().contains(searchString) ?? false })
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
            DataManager.shared.clearHistory()
            self.reloadHistory()
        }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
        present(alertView, animated: true)
    }
}

// MARK: - Table View Data Source
extension HistoryViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        filteredSearchEntries.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredSearchEntries[section].1.count
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        20
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        12
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SourceSectionHeaderView") as? SourceSectionHeaderView
        view?.title.text = self.tableView(tableView, titleForHeaderInSection: section)
        return view
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let days = filteredSearchEntries[section].0
        let now = Date()
        let date = now.addingTimeInterval(-86400 * Double(days))
        let difference = Calendar.autoupdatingCurrent.dateComponents(Set([Calendar.Component.day]), from: date, to: now)

        // today or yesterday
        if days < 2 {
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .medium
            formatter.doesRelativeDateFormatting = true
            return formatter.string(from: date)
        } else if days < 8 { // n days ago
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .short
            formatter.allowedUnits = .day
            guard let timePhrase = formatter.string(from: difference) else { return "" }
            return String(format: NSLocalizedString("%@_AGO", comment: ""), timePhrase)
        } else { // mm/dd/yy
            let formatter = DateFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "HistoryTableViewCell", for: indexPath) as? HistoryTableViewCell
        if cell == nil {
            cell = HistoryTableViewCell(reuseIdentifier: "HistoryTableViewCell")
        }
        guard let cell = cell else { return UITableViewCell() }
        cell.entry = filteredSearchEntries[indexPath.section].1[indexPath.row]
        return cell
    }
}

// MARK: - Table View Delegate
extension HistoryViewController {

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let entry = entries[indexPath.section].1[indexPath.row]
        navigationController?.pushViewController(
            MangaViewController(manga: entry.manga),
            animated: true
        )
        tableView.deselectRow(at: indexPath, animated: true)
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard searchText.isEmpty else { return } // disable load more while searching
        if indexPath.section == entries.count - 1 && indexPath.row == (entries.last?.1.count ?? 1) - 1 {
            fetchNewEntries()
        }
    }

    override func tableView(
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
                DataManager.shared.removeHistory(for: entry.chapter)
                self.reloadHistory()
                completion(true)
            })
            alertView.addAction(UIAlertAction(title: NSLocalizedString("REMOVE_ALL_MANGA_HISTORY", comment: ""), style: .destructive) { _ in
                DataManager.shared.removeHistory(for: entry.manga)
                self.reloadHistory()
                completion(true)
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

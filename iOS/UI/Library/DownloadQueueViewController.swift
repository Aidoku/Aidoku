//
//  DownloadQueueViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/17/22.
//

import UIKit

class DownloadQueueViewController: UITableViewController {

    var queue: [(sourceId: String, downloads: [Download])] = []

    var observers: [NSObjectProtocol] = []
    var chapters: [Chapter] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        for chapter in chapters {
            Task {
                await DownloadManager.shared.removeProgressBlock(for: chapter)
            }
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // swiftlint:disable:next cyclomatic_complexity
    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("DOWNLOAD_QUEUE", comment: "")
        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        tableView.register(DownloadTableViewCell.self, forCellReuseIdentifier: "DownloadTableViewCell")

        // add download to queue list
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadsQueued"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let downloads = notification.object as? [Download] {
                var sectionsToInsert: [Int] = []
                var rowsToInsert: [IndexPath] = []

                for download in downloads {
                    let index = self.queue.firstIndex(where: { $0.sourceId == download.sourceId })
                    var downloads = index != nil ? self.queue[index!].downloads : []
                    downloads.append(download)
                    if let index = index {
                        self.queue[index].downloads = downloads
                        rowsToInsert.append(IndexPath(row: downloads.count - 1, section: index))
                    } else {
                        self.queue.append((download.sourceId, downloads))
                        sectionsToInsert.append(self.queue.count - 1)
                    }
                }

                let newSections = sectionsToInsert
                let newRows = rowsToInsert

                Task { @MainActor in
                    self.tableView.performBatchUpdates {
                        if !newSections.isEmpty {
                            self.tableView.insertSections(IndexSet(newSections), with: .automatic)
                        }
                        if !newRows.isEmpty {
                            self.tableView.insertRows(at: newRows, with: .automatic)
                        }
                    }
                    self.updateClearButton()
                }

            }
        })

        let clearDownloadBlock: (Notification) -> Void = { [weak self] notification in
            guard let self = self else { return }
            if let download = notification.object as? Download,
               let index = self.queue.firstIndex(where: { $0.sourceId == download.sourceId }) {
                var downloads = self.queue[index].downloads
                let indexToRemove = downloads.firstIndex(where: { $0 == download })
                guard let indexToRemove = indexToRemove else { return } // nothing to remove
                downloads.remove(at: indexToRemove)
                if downloads.isEmpty {
                    self.queue.remove(at: index)
                    Task { @MainActor in
                        self.tableView.performBatchUpdates {
                            self.tableView.deleteSections(IndexSet(integer: index), with: .fade)
                        }
                        self.updateClearButton()
                    }
                } else {
                    self.queue[index].downloads = downloads
                    Task { @MainActor in
                        self.tableView.performBatchUpdates {
                            self.tableView.deleteRows(at: [IndexPath(row: indexToRemove, section: index)], with: .automatic)
                        }
                        self.updateClearButton()
                    }
                }
            }
        }

        // remove download from queue list
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadFinished"), object: nil, queue: nil, using: clearDownloadBlock
        ))

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadCancelled"), object: nil, queue: nil, using: clearDownloadBlock
        ))

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadsCancelled"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if notification.object == nil { // all downloads cleared
                self.queue.removeAll()
                Task { @MainActor in
                    self.tableView.deleteSections(IndexSet(integersIn: 0..<self.tableView.numberOfSections), with: .fade)
                    self.updateClearButton()
                }
            }
        })

        // get initial download queue
        Task {
            let globalQueue = await DownloadManager.shared.getDownloadQueue()
            var queue: [(String, [Download])] = []
            for queueObject in globalQueue where !queueObject.value.isEmpty {
                queue.append((queueObject.key, queueObject.value))
            }
            await MainActor.run {
                self.queue = queue
                self.tableView.reloadData()
                self.updateClearButton()
            }
        }
    }

    func updateClearButton() {
        if !queue.isEmpty {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: NSLocalizedString("CLEAR", comment: ""),
                style: .plain,
                target: self,
                action: #selector(clearQueue)
            )
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }

    @objc func clearQueue() {
        DownloadManager.shared.cancelDownloads()
    }

    @objc func close() {
        dismiss(animated: true)
    }
}

// MARK: - Table View Data Source
extension DownloadQueueViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        queue.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        queue[section].downloads.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let id = queue[section].sourceId
        let source = SourceManager.shared.source(for: id)
        return source?.manifest.info.name
    }

    // swiftlint:disable:next cyclomatic_complexity
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "DownloadTableViewCell")
        if cell == nil {
            cell = DownloadTableViewCell(reuseIdentifier: "DownloadTableViewCell")
        }
        guard let cell = cell as? DownloadTableViewCell else { return UITableViewCell() }

        let download = queue[indexPath.section].downloads[indexPath.row]

        if let manga = download.manga {
            cell.titleLabel.text = manga.title ?? NSLocalizedString("UNTITLED", comment: "")
        } else {
            let manga = CoreDataManager.shared.getManga(sourceId: download.sourceId, mangaId: download.mangaId)
            cell.titleLabel.text = manga?.title ?? NSLocalizedString("UNTITLED", comment: "")
        }

        if let chapter = download.chapter {
            var text = ""
            if let num = chapter.chapterNum {
                text += String(format: NSLocalizedString("CHAPTER_X", comment: ""), num)
                if chapter.title != nil {
                    text += ": "
                }
            }
            if let title = chapter.title {
                text += title
            }
            cell.subtitleLabel.text = text
        }

        cell.subtitleLabel.textColor = .secondaryLabel
        cell.selectionStyle = .none

        cell.total = download.total
        cell.progress = download.progress

        // progress update block
        if let chapter = download.chapter {
            if !chapters.contains(chapter) {
                chapters.append(chapter)
            }
            DownloadManager.shared.onProgress(for: chapter) { [weak self] progress, total in
                guard let self = self else { return }
                if let queueIndex = self.queue.firstIndex(where: { $0.sourceId == download.sourceId }),
                   let downloadIndex = self.queue[queueIndex].downloads.firstIndex(where: { $0 == download }) {
                    self.queue[queueIndex].downloads[downloadIndex].progress = progress
                    self.queue[queueIndex].downloads[downloadIndex].total = total

                    Task { @MainActor in
                        if let cell = tableView.cellForRow(at: IndexPath(row: queueIndex, section: downloadIndex)) as? DownloadTableViewCell {
                            if total != cell.total { cell.total = total }
                            cell.progress = progress
                        }
                    }
                }
            }
        }

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let cancelAction = UIContextualAction(style: .destructive, title: NSLocalizedString("CANCEL", comment: "")) { _, _, completion in
            if let chapter = self.queue[indexPath.section].downloads[indexPath.row].chapter {
                DownloadManager.shared.cancelDownload(for: chapter)
                completion(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [cancelAction])
    }
}

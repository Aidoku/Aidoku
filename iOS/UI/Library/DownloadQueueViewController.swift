//
//  DownloadQueueViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/17/22.
//

import UIKit

class DownloadQueueViewController: UITableViewController {

    var queue: [(sourceId: String, downloads: [Download])] = []

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Download Queue"
        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        tableView.register(DownloadTableViewCell.self, forCellReuseIdentifier: "DownloadTableViewCell")

        // add download to queue list
        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadQueued"), object: nil, queue: nil) { notification in
            if let download = notification.object as? Download {
                let index = self.queue.firstIndex(where: { $0.sourceId == download.sourceId })
                var downloads = index != nil ? self.queue[index!].downloads : []
                downloads.append(download)
                if let index = index {
                    let downloads = downloads
                    self.queue[index].downloads = downloads
                    Task { @MainActor in
                        self.tableView.insertRows(at: [IndexPath(row: downloads.count - 1, section: index)], with: .automatic)
                    }
                } else {
                    self.queue.append((download.sourceId, downloads))
                    Task { @MainActor in
                        self.tableView.performBatchUpdates {
                            self.tableView.insertSections(IndexSet(integer: self.queue.count - 1), with: .automatic)
                        }
                    }
                }
            }
        }

        // remove download from queue list
        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadFinished"), object: nil, queue: nil) { notification in
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
                    }
                } else {
                    self.queue[index].downloads = downloads
                    Task { @MainActor in
                        self.tableView.performBatchUpdates {
                            self.tableView.deleteRows(at: [IndexPath(row: indexToRemove, section: index)], with: .automatic)
                        }
                    }
                }
            }
        }

        // get initial download queue
        Task {
            let globalQueue = await DownloadManager.shared.getDownloadQueue()
            self.queue = []
            for queueObject in globalQueue where !queueObject.value.isEmpty {
                self.queue.append((queueObject.key, queueObject.value))
            }
            Task { @MainActor in
                self.tableView.reloadData()
            }
        }
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
            let manga = DataManager.shared.getMangaObject(withId: download.mangaId, sourceId: download.sourceId)
            cell.titleLabel.text = manga?.title ?? NSLocalizedString("UNTITLED", comment: "")
        }

        if let chapter = download.chapter {
            var text = ""
            if let num = chapter.chapterNum {
                text += String(format: "Chapter %g", num)
            }
            if let title = chapter.title {
                text += ": \(title)"
            }
            cell.subtitleLabel.text = text
        }

        cell.subtitleLabel.textColor = .secondaryLabel
        cell.selectionStyle = .none

        cell.total = download.total
        cell.progress = download.progress

        // progress update block
        if let chapter = download.chapter {
            DownloadManager.shared.onProgress(for: chapter) { progress, total in
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

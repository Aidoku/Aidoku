//
//  BackupsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/26/22.
//

import UIKit
import CoreData

class BackupsViewController: UITableViewController {

    var backups = BackupManager.backupUrls

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Backups"

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createBackup))

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("updateBackupList"), object: nil, queue: nil) { _ in
            let previousBackups = self.backups
            self.backups = BackupManager.backupUrls
            let previousCount = previousBackups.count
            let currentCount = self.backups.count
            if previousCount == currentCount {
                self.tableView.reloadData()
            } else {
                self.tableView.performBatchUpdates {
                    if previousCount > currentCount { // remove
                        for (i, url) in previousBackups.enumerated() {
                            if !self.backups.contains(url) {
                                self.tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .fade)
                            }
                        }
                    } else { // add
                        for url in self.backups {
                            if !previousBackups.contains(url) {
                                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                            }
                        }
                    }
                }
            }
        }
    }

    @objc func createBackup() {
        BackupManager.shared.saveNewBackup()
    }
}

// MARK: - Table View Data Source
extension BackupsViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        backups.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
        }

        if let backup = Backup.load(from: backups[indexPath.row]) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/dd h:mm a"
            cell?.textLabel?.text = "Backup \(dateFormatter.string(from: backup.date))"
        } else {
            cell?.textLabel?.text = "Corrupted Backup"
        }

        return cell ?? UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let alertView = UIAlertController(
            title: "Restore to this backup?",
            message: "All current data will be removed and replaced by the data from this backup.",
            preferredStyle: .actionSheet
        )

        let action = UIAlertAction(title: "Restore", style: .destructive) { _ in
            if let backup = Backup.load(from: self.backups[indexPath.row]) {
                BackupManager.shared.restore(from: backup)
            }
        }
        alertView.addAction(action)

        alertView.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alertView, animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            BackupManager.shared.removeBackup(url: backups[indexPath.row])
        }
    }

    override func tableView(_ tableView: UITableView,
                            contextMenuConfigurationForRowAt indexPath: IndexPath,
                            point: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ -> UIMenu? in
            let action = UIAction(title: "Export", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.present(UIActivityViewController(activityItems: [self.backups[indexPath.row]], applicationActivities: nil),
                             animated: true)
            }
            return UIMenu(title: "", children: [action])
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Long press on a backup to export it, or swipe to the left to delete."
    }
}

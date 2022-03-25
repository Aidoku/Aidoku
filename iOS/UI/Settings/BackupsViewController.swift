//
//  BackupsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/26/22.
//

import UIKit
import CoreData

class BackupsViewController: UITableViewController {

    var backups: [URL] = []

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

        Task { @MainActor in
            backups = BackupManager.backupUrls
            tableView.reloadSections(IndexSet(integer: 0), with: .fade)
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
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCellSubtitle")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UITableViewCellSubtitle")
        }

        cell?.detailTextLabel?.text = nil

        if let backup = Backup.load(from: backups[indexPath.row]) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/dd h:mm a"
            if let name = backup.name {
                cell?.textLabel?.text = name
                cell?.detailTextLabel?.text = dateFormatter.string(from: backup.date)
                cell?.detailTextLabel?.textColor = .secondaryLabel
            } else {
                cell?.textLabel?.text = "Backup \(dateFormatter.string(from: backup.date))"
            }
        } else {
            cell?.textLabel?.text = "Corrupted Backup"
        }

        return cell!
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let alertView = UIAlertController(
            title: "Restore to this backup?",
            message: "All current data will be removed and replaced by the data from this backup.",
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
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

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {

        let rename = UIContextualAction(style: .normal, title: "Rename") { _, _, completion in
            if let backup = Backup.load(from: self.backups[indexPath.row]) {
                let alert = UIAlertController(title: "Rename Backup", message: "Enter a new name for your backup", preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.placeholder = backup.name ?? "Backup Name"
                }
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in }))
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    let textField = alert.textFields![0]
                    BackupManager.shared.renameBackup(url: self.backups[indexPath.row], name: textField.text)
                }))
                self.present(alert, animated: true, completion: nil)
            } else {
                let alert = UIAlertController(
                    title: "Corrupted Backup",
                    message: "This backup seems to have misconfigured data. Renaming is not possible.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in }))
                self.present(alert, animated: true, completion: nil)
            }
            completion(true)
        }
        rename.backgroundColor = .systemIndigo

        let delete = UIContextualAction(style: .normal, title: "Delete") { _, _, completion in
            BackupManager.shared.removeBackup(url: self.backups[indexPath.row])
            completion(true)
        }
        delete.backgroundColor = .red

        return UISwipeActionsConfiguration(actions: [delete, rename])
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

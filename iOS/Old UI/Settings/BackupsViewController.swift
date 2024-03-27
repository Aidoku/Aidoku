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

    var observers: [NSObjectProtocol] = []

    var loadingAlert: UIAlertController?

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("BACKUPS", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createBackup))

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        Task { @MainActor in
            backups = BackupManager.backupUrls
            tableView.reloadSections(IndexSet(integer: 0), with: .fade)
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateBackupList"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let previousBackups = self.backups
                self.backups = BackupManager.backupUrls
                let previousCount = previousBackups.count
                let currentCount = self.backups.count
                if previousCount == currentCount {
                    self.tableView.reloadData()
                } else {
                    self.tableView.performBatchUpdates {
                        if previousCount > currentCount { // remove
                            for (i, url) in previousBackups.enumerated() where !self.backups.contains(url) {
                                self.tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .fade)
                            }
                        } else { // add
                            for url in self.backups where !previousBackups.contains(url) {
                                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .automatic)
                            }
                        }
                    }
                }
            }
        })
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
        present(loadingAlert!, animated: true)
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
            let date = DateFormatter.localizedString(from: backup.date, dateStyle: .short, timeStyle: .short)
            if let name = backup.name {
                cell?.textLabel?.text = name
                cell?.detailTextLabel?.text = date
                cell?.detailTextLabel?.textColor = .secondaryLabel
            } else {
                cell?.textLabel?.text = "Backup \(date)"
            }
        } else {
            cell?.textLabel?.text = NSLocalizedString("CORRUPTED_BACKUP", comment: "")
        }

        let label = UILabel()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: backups[indexPath.row].path),
           let size = attributes[FileAttributeKey.size] as? Int64 {
            label.text = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            label.text = nil
        }
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.sizeToFit()
        cell?.accessoryView = label

        return cell!
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let restoreAlert = UIAlertController(
            title: NSLocalizedString("RESTORE_BACKUP", comment: ""),
            message: NSLocalizedString("RESTORE_BACKUP_TEXT", comment: ""),
            preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
        )

        restoreAlert.addAction(UIAlertAction(title: NSLocalizedString("RESTORE", comment: ""), style: .destructive) { _ in
            if let backup = Backup.load(from: self.backups[indexPath.row]) {
                self.showLoadingIndicator()
                Task { @MainActor in
                    do {
                        try await BackupManager.shared.restore(from: backup)
                        self.loadingAlert?.dismiss(animated: true)

                        let missingSources = (backup.sources ?? []).filter {
                            !CoreDataManager.shared.hasSource(id: $0)
                        }
                        if !missingSources.isEmpty {
                            var message = NSLocalizedString("MISSING_SOURCES_TEXT", comment: "")
                            message += missingSources.map { "\n- \($0)" }.joined()
                            let missingAlert = UIAlertController(
                                title: NSLocalizedString("MISSING_SOURCES", comment: ""),
                                message: message,
                                preferredStyle: .alert
                            )
                            missingAlert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
                            self.present(missingAlert, animated: true)
                        }
                    } catch {
                        let errorValue = (error as? BackupManager.BackupError)?.stringValue ?? "Unknown"
                        self.loadingAlert?.dismiss(animated: true)
                        let errorAlert = UIAlertController(
                            title: NSLocalizedString("BACKUP_ERROR", comment: ""),
                            message: String(format: NSLocalizedString("BACKUP_ERROR_TEXT", comment: ""), errorValue),
                            preferredStyle: .alert
                        )
                        errorAlert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        })

        restoreAlert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
        present(restoreAlert, animated: true)
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {

        let rename = UIContextualAction(style: .normal, title: NSLocalizedString("RENAME", comment: "")) { _, _, completion in
            if let backup = Backup.load(from: self.backups[indexPath.row]) {
                let alert = UIAlertController(title: NSLocalizedString("RENAME_BACKUP", comment: ""),
                                              message: NSLocalizedString("RENAME_BACKUP_TEXT", comment: ""), preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.placeholder = backup.name ?? NSLocalizedString("BACKUP_NAME", comment: "")
                }
                alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel, handler: { _ in }))
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { _ in
                    let textField = alert.textFields![0]
                    BackupManager.shared.renameBackup(url: self.backups[indexPath.row], name: textField.text)
                }))
                self.present(alert, animated: true)
            } else {
                let alert = UIAlertController(
                    title: NSLocalizedString("CORRUPTED_BACKUP", comment: ""),
                    message: NSLocalizedString("CORRUPTED_BACKUP_TEXT", comment: ""),
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: { _ in }))
                self.present(alert, animated: true)
            }
            completion(true)
        }
        rename.backgroundColor = .systemIndigo

        let delete = UIContextualAction(style: .normal, title: NSLocalizedString("DELETE", comment: "")) { _, _, completion in
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
            let action = UIAction(title: NSLocalizedString("EXPORT", comment: ""), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                let vc = UIActivityViewController(activityItems: [self.backups[indexPath.row]], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = tableView
                vc.popoverPresentationController?.sourceRect = tableView.cellForRow(at: indexPath)!.frame
                self.present(vc, animated: true)
            }
            return UIMenu(title: "", children: [action])
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        NSLocalizedString("BACKUP_INFO", comment: "")
    }
}

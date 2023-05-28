//
//  SourceListsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 4/20/22.
//

import UIKit

class SourceListsViewController: UITableViewController {

    var sourceLists: [URL] = SourceManager.shared.sourceLists

    var observers: [NSObjectProtocol] = []

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

        title = NSLocalizedString("SOURCE_LISTS", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addSourceList))

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("updateSourceLists"), object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let previousLists = self.sourceLists
                self.sourceLists = SourceManager.shared.sourceLists
                if previousLists.count == self.sourceLists.count {
                    self.tableView.reloadData()
                } else {
                    self.tableView.performBatchUpdates {
                        if previousLists.count > self.sourceLists.count { // remove
                            for (i, url) in previousLists.enumerated() where !self.sourceLists.contains(url) {
                                self.tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .fade)
                            }
                        } else { // add
                            for (i, url) in self.sourceLists.enumerated() where !previousLists.contains(url) {
                                self.tableView.insertRows(at: [IndexPath(row: i, section: 0)], with: .automatic)
                            }
                        }
                    }
                }
            }
        })
    }

    @objc func addSourceList() {
        let alert = UIAlertController(
            title: NSLocalizedString("SOURCE_LIST_ADD", comment: ""),
            message: NSLocalizedString("SOURCE_LIST_ADD_TEXT", comment: ""),
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = NSLocalizedString("SOURCE_LIST_URL", comment: "")
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            textField.keyboardType = .URL
            textField.returnKeyType = .done
        }

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default) { _ in
            guard let textField = alert.textFields?.first else { return }
            if let urlString = textField.text,
               let url = URL(string: urlString) {
                Task {
                    let success = await SourceManager.shared.addSourceList(url: url)
                    if !success {
                        let alert = UIAlertController(
                            title: NSLocalizedString("SOURCE_LIST_ADD_FAIL", comment: ""),
                            message: NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT", comment: ""),
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel))
                        self.present(alert, animated: true)
                    }
                }
            }
        })

        self.present(alert, animated: true)
    }
}

// MARK: - Table View Data Source
extension SourceListsViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sourceLists.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell")
        if cell == nil {
            cell = UITableViewCell(style: .default, reuseIdentifier: "UITableViewCell")
        }

        cell?.textLabel?.text = sourceLists[indexPath.row].absoluteString
        cell?.selectionStyle = .none

        return cell!
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            SourceManager.shared.removeSourceList(url: sourceLists[indexPath.row])
        }
    }
}

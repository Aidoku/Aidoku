//
//  SettingSelectViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/16/22.
//

import UIKit

class SettingSelectViewController: UITableViewController {

    let source: Source?
    let item: SettingItem

    var multi: Bool {
        item.type == "multi-select" || item.type == "multi-single-select"
    }
    var forceSingle: Bool {
        item.type == "multi-single-select"
    }

    // single
    var value: String {
        get {
            UserDefaults.standard.string(forKey: item.key ?? "") ?? ""
        }
        set {
            if let key = item.key {
                UserDefaults.standard.set(newValue, forKey: key)
            }
        }
    }
    var index: Int {
        item.values?.firstIndex(of: value) ?? -1
    }

    // multi
    var values: [String] {
        get {
            (UserDefaults.standard.array(forKey: item.key ?? "") as? [String]) ?? []
        }
        set {
            if let key = item.key {
                UserDefaults.standard.set(newValue, forKey: key)
            }
        }
    }
    var indexes: [Int] {
        var indexes = [Int]()
        for value in values {
            if let index = item.values?.firstIndex(of: value) {
                indexes.append(index)
            }
        }
        return indexes
    }

    init(source: Source? = nil, item: SettingItem, style: UITableView.Style = .insetGrouped) {
        self.source = source
        self.item = item
        super.init(style: style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = item.title

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.delaysContentTouches = false

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = false
    }
}

// MARK: - Table View Data Source
extension SettingSelectViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        item.values?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        item.footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)

        if indexPath.row < item.values?.count ?? 0 {
            cell.textLabel?.text = item.titles?[indexPath.row] ?? item.values?[indexPath.row]
            cell.accessoryType = .none
            if multi {
                if indexes.contains(indexPath.row) {
                    cell.accessoryType = .checkmark
                }
            } else if index == indexPath.row {
                cell.accessoryType = .checkmark
            }
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if multi && !forceSingle {
            if let cell = tableView.cellForRow(at: indexPath), let itemValues = item.values {
                if cell.accessoryType == .checkmark {
                    cell.accessoryType = .none
                    values.removeAll(where: { $0 == itemValues[indexPath.row] })
                } else {
                    cell.accessoryType = .checkmark
                    values.append(itemValues[indexPath.row])
                }
            }
        } else {
            if let itemValues = item.values, indexPath.row < itemValues.count {
                if forceSingle {
                    values.compactMap { itemValues.firstIndex(of: $0) }.forEach {
                        tableView.cellForRow(at: IndexPath(row: $0, section: 0))?.accessoryType = .none
                    }
                    values = [itemValues[indexPath.row]]
                } else {
                    tableView.cellForRow(at: IndexPath(row: index, section: 0))?.accessoryType = .none
                    value = itemValues[indexPath.row]
                }
                tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
            }
        }
        if let notification = item.notification {
            source?.performAction(key: notification)
            NotificationCenter.default.post(name: NSNotification.Name(notification), object: nil)
        }
        if let key = item.key {
            NotificationCenter.default.post(name: NSNotification.Name(key), object: multi ? values : value)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

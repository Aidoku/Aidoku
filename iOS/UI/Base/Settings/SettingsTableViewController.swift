//
//  SettingsTableViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/27/22.
//

import UIKit
import SafariServices

class SettingsTableViewController: UITableViewController {

    var items: [SettingItem]

    var observers: [SettingItem] = []

    init(items: [SettingItem] = []) {
        self.items = items
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Settings"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.hidesSearchBarWhenScrolling = false

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationItem.hidesSearchBarWhenScrolling = true
    }
}

// MARK: - Table View Data Source
extension SettingsTableViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items[section].items?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        items[section].title
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath,
                   settingItem item: SettingItem) -> UITableViewCell {
        let cell: UITableViewCell
        switch item.type {
        case "select":
            cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")

            if let value = UserDefaults.standard.string(forKey: item.key ?? ""),
               let index = item.values?.firstIndex(of: value) {
                cell.detailTextLabel?.text = item.titles?[index]
            }
            cell.accessoryType = .disclosureIndicator

        case "multi-select", "page":
            cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            cell.textLabel?.textColor = .label
            cell.accessoryType = .disclosureIndicator

        case "switch":
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UITableViewCell.Subtitle")

            cell.detailTextLabel?.text = item.subtitle
            cell.detailTextLabel?.textColor = .secondaryLabel
            let switchView = UISwitch()
            switchView.defaultsKey = item.key ?? ""
            switchView.handleChange { _ in
                if let notification = item.notification {
                    NotificationCenter.default.post(name: NSNotification.Name(notification), object: item)
                }
            }
            if let requires = item.requires {
                switchView.isEnabled = UserDefaults.standard.bool(forKey: requires)
                NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                    switchView.isEnabled = UserDefaults.standard.bool(forKey: requires)
                }
                observers.append(item)
            } else if let requires = item.requiresFalse {
                switchView.isEnabled = !UserDefaults.standard.bool(forKey: requires)
                NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                    switchView.isEnabled = !UserDefaults.standard.bool(forKey: requires)
                }
                observers.append(item)
            } else {
                switchView.isEnabled = true
            }
            cell.accessoryView = switchView
            cell.selectionStyle = .none

        case "button", "link":
            cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            if item.destructive ?? false {
                cell.textLabel?.textColor = .systemRed
            } else {
                cell.textLabel?.textColor = view.tintColor
            }
            cell.accessoryType = .none

        case "text":
            cell = TextInputTableViewCell(reuseIdentifier: "TextInputTableViewCell")
            (cell as? TextInputTableViewCell)?.item = item

        case "segment":
            cell = SegmentTableViewCell(item: item, reuseIdentifier: nil)

        default:
            cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            cell.textLabel?.textColor = .label
            cell.accessoryType = .none
        }

        cell.textLabel?.text = item.title

        return cell
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if let item = items[indexPath.section].items?[indexPath.row] {
            return self.tableView(tableView, cellForRowAt: indexPath, settingItem: item)
        } else {
            return tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let item = items[indexPath.section].items?[indexPath.row] {
            if item.type == "link" {
                if let url = URL(string: item.key ?? "") {
                    if let external = item.external, external {
                        UIApplication.shared.open(url)
                    } else {
                        let safariViewController = SFSafariViewController(url: url)
                        present(safariViewController, animated: true)
                    }
                }
            } else if item.type == "page", let items = item.items {
                let subPage = SettingsTableViewController(items: items)
                subPage.title = item.title
                present(subPage, animated: true)
            }
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

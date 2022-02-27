//
//  SourceInfoViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/15/22.
//

import UIKit
import SafariServices

class SourceInfoViewController: SettingsTableViewController {

    var source: Source

    init(source: Source) {
        self.source = source
        super.init(items: source.settingItems)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Source Info"
        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.delaysContentTouches = false
        tableView.keyboardDismissMode = .onDrag

        let headerView = SourceInfoHeaderView(source: source)
        headerView.frame.size.height = 48 + 32 + 20
        tableView.tableHeaderView = headerView

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        tableView.register(TextInputTableViewCell.self, forCellReuseIdentifier: "TextInputTableViewCell")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        source.needsFilterRefresh = true
    }

    @objc func close() {
        dismiss(animated: true)
    }
}

// MARK: - Table View Data Source
extension SourceInfoViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + source.settingItems.count + (source.languages.isEmpty ? 0 : 1)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !source.languages.isEmpty && section == 0 {
            return 1
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return 2
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].items?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !source.languages.isEmpty && section == 0 {
            return "Language"
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return "Info"
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if !source.languages.isEmpty && section == 0 {
            return nil
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return nil
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if !source.languages.isEmpty && indexPath.section == 0 { // Language selection
            var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell.Value1")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            }

            cell?.textLabel?.text = "Language"
            if let value = UserDefaults.standard.string(forKey: "\(source.id)._language"),
               let index = source.languages.firstIndex(of: value) {
                cell?.detailTextLabel?.text = source.languages[index]
            }
            cell?.accessoryType = .disclosureIndicator

            return cell!
        } else if source.settingItems.isEmpty
                    || indexPath.section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) { // Footer info
            var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell.Value1")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            }

            switch indexPath.row {
            case 0:
                cell?.textLabel?.text = "Version"
                cell?.detailTextLabel?.text = String(source.info.version)
            case 1:
                cell?.textLabel?.text = "Language"
                cell?.detailTextLabel?.text = source.info.lang
            default:
                break
            }

            cell?.accessoryType = .none
            cell?.selectionStyle = .none

            return cell!
        } else if let item = source.settingItems[indexPath.section + (source.languages.isEmpty ? 0 : -1)].items?[indexPath.row] { // Settings
            return self.tableView(tableView, cellForRowAt: indexPath, settingItem: item)
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !source.languages.isEmpty && indexPath.section == 0 {
            let item = SettingItem(
                type: "select",
                key: "_language",
                title: "Language",
                values: source.languages,
                titles: source.languages,
                notification: "languageChange"
            )
            navigationController?.pushViewController(SourceSettingSelectViewController(source: source, item: item), animated: true)
        } else if source.settingItems.isEmpty || indexPath.section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            // info
        } else if let item = source.settingItems[indexPath.section + (source.languages.isEmpty ? 0 : -1)].items?[indexPath.row] {
            if item.type == "select" || item.type == "multi-select" {
                navigationController?.pushViewController(SourceSettingSelectViewController(source: source, item: item), animated: true)
            } else if item.type == "button" {
                if let key = item.action {
                    source.performAction(key: key)
                }
            } else {
                super.tableView(tableView, didSelectRowAt: indexPath)
            }
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

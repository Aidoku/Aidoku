//
//  SourceInfoViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/15/22.
//

import UIKit
import SafariServices

class SourceInfoViewController: SettingsTableViewController {

    init(source: Source, subPage: Bool = false) {
        super.init(items: source.settingItems)
        self.source = source
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SOURCE_INFO", comment: "")
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

        guard let source = source else { return }
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
        source?.needsFilterRefresh = true
    }

    @objc func close() {
        dismiss(animated: true)
    }
}

// MARK: - Table View Data Source
extension SourceInfoViewController {

    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + (source?.settingItems.count ?? 0) + (source?.languages.isEmpty ?? true ? 0 : 1)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let source = source else { return 0 }
        if !source.languages.isEmpty && section == 0 {
            return 1
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return 2
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].items?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let source = source else { return nil }
        if !source.languages.isEmpty && section == 0 {
            return NSLocalizedString("LANGUAGE", comment: "")
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return NSLocalizedString("INFO", comment: "")
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let source = source else { return nil }
        if !source.languages.isEmpty && section == 0 {
            return nil
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return nil
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let source = source else { return UITableViewCell() }
        if !source.languages.isEmpty && indexPath.section == 0 { // Language selection
            var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell.Value1")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            }

            cell?.textLabel?.text = NSLocalizedString("LANGUAGE", comment: "")
//            if let value = UserDefaults.standard.array(forKey: "\(source.id).languages").first,
//               let index = source.languages.firstIndex(of: value) {
//                cell?.detailTextLabel?.text = source.languages[index]
//            }
            cell?.detailTextLabel?.text = nil
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
                cell?.textLabel?.text = NSLocalizedString("VERSION", comment: "")
                cell?.detailTextLabel?.text = String(source.manifest.info.version)
            case 1:
                cell?.textLabel?.text = NSLocalizedString("LANGUAGE", comment: "")
                cell?.detailTextLabel?.text = source.manifest.info.lang
            default:
                break
            }

            cell?.accessoryType = .none
            cell?.selectionStyle = .none

            return cell!
        } else if let item = source.settingItems[indexPath.section + (source.languages.isEmpty ? 0 : -1)].items?[indexPath.row] { // Settings
            let cell = self.tableView(tableView, cellForRowAt: indexPath, settingItem: item)
            if item.type == "text" {
                (cell as? TextInputTableViewCell)?.source = source
            } else if item.type == "segment" {
                (cell as? SegmentTableViewCell)?.source = source
            }
            return cell
        }

        return UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let source = source else { return }
        if !source.languages.isEmpty && indexPath.section == 0 {
            let item = SettingItem(
                type: source.manifest.languageSelectType == "single" ? "multi-single-select" : "multi-select",
                key: "\(source.id).languages",
                title: NSLocalizedString("LANGUAGE", comment: ""),
                values: source.languages.map { $0.value ?? $0.code },
                titles: source.languages.map { (Locale.current as NSLocale).displayName(forKey: .identifier, value: $0.code) ?? $0.code },
                notification: "languageChange"
            )
            navigationController?.pushViewController(SettingSelectViewController(source: source, item: item, style: tableView.style), animated: true)
        } else if source.settingItems.isEmpty || indexPath.section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            // info
        } else if let item = source.settingItems[indexPath.section + (source.languages.isEmpty ? 0 : -1)].items?[indexPath.row] {
            performAction(for: item, at: indexPath)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

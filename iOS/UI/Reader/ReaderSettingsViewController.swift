//
//  ReaderSettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/27/22.
//

import UIKit

class ReaderSettingsViewController: SettingsTableViewController {

    init() {
        super.init(items: [
            SettingItem(type: "group", title: "General", items: [
                SettingItem(type: "select", key: "Reader.readingMode", title: "Reading Mode",
                            values: ["default", "rtl", "ltr", "vertical", "scroll"],
                            titles: ["Default", "Right to Left", "Left to Right", "Vertical", "Vertical Scroll"])
            ])
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Reader Settings"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
    }

    @objc func close() {
        dismiss(animated: true)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let item = items[indexPath.section].items?[indexPath.row] {
            if item.type == "select" || item.type == "multi-select" {
                let vc = SettingSelectViewController(item: item, style: tableView.style)
                navigationController?.pushViewController(vc, animated: true)
                tableView.deselectRow(at: indexPath, animated: true)
            } else {
                super.tableView(tableView, didSelectRowAt: indexPath)
            }
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }
}

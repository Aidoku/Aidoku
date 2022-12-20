//
//  ReaderSettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit

class ReaderSettingsViewController: SettingsTableViewController {

    init() {
        super.init(items: [
            SettingItem(type: "group", title: NSLocalizedString("GENERAL", comment: ""), items: [
                SettingItem(
                    type: "select",
                    key: "Reader.readingMode",
                    title: NSLocalizedString("READING_MODE", comment: ""),
                    values: ["default", "rtl", "ltr", "vertical", "scroll"],
                    titles: [
                        NSLocalizedString("DEFAULT", comment: ""),
                        NSLocalizedString("RTL", comment: ""),
                        NSLocalizedString("LTR", comment: ""),
                        NSLocalizedString("VERTICAL", comment: ""),
                        NSLocalizedString("VERTICAL_SCROLL", comment: "")
                    ],
                    notification: "Reader.readingMode"
                ),
                SettingItem(type: "switch", key: "Reader.downsampleImages", title: NSLocalizedString("DOWNSAMPLE_IMAGES", comment: "")),
                SettingItem(type: "switch", key: "Reader.saveImageOption", title: NSLocalizedString("SAVE_IMAGE_OPTION", comment: "")),
                SettingItem(
                    type: "stepper",
                    key: "Reader.pagesToPreload",
                    title: NSLocalizedString("PAGES_TO_PRELOAD", comment: ""),
                    minimumValue: 1,
                    maximumValue: 10
                )
            ])
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("READER_SETTINGS", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )

        updateReaderModeSettings()

        addObserver(forName: "Reader.readingMode") { [weak self] _ in
            self?.updateReaderModeSettings()
            self?.tableView.reloadData()
        }
    }

    // fetch settings for current reader mode
    func updateReaderModeSettings() {
        let mode = UserDefaults.standard.string(forKey: "Reader.readingMode")

        items = [items[0]]

        switch mode {
        case "rtl", "ltr", "vertical": // paged
            items.append(ReaderPagedViewModel.settings)
        case "scroll", "webtoon": // scroll
            items.append(ReaderWebtoonViewModel.settings)
        default: // all settings
            items.append(ReaderPagedViewModel.settings)
            items.append(ReaderWebtoonViewModel.settings)
        }
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

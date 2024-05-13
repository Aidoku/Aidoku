//
//  ReaderSettingsViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 9/27/22.
//

import UIKit

class ReaderSettingsViewController: SettingsTableViewController {

    init(mangaId: String) {
        super.init(items: [SettingItem(type: "group", title: NSLocalizedString("GENERAL", comment: ""), items: [
            SettingItem(
                type: "select",
                key: "Reader.readingMode.\(mangaId)",
                title: NSLocalizedString("READING_MODE", comment: ""),
                values: ["default", "auto", "rtl", "ltr", "vertical", "webtoon"],
                titles: [
                    NSLocalizedString("DEFAULT", comment: ""),
                    NSLocalizedString("AUTOMATIC", comment: ""),
                    NSLocalizedString("RTL", comment: ""),
                    NSLocalizedString("LTR", comment: ""),
                    NSLocalizedString("VERTICAL", comment: ""),
                    NSLocalizedString("WEBTOON", comment: "")
                ],
                notification: "Reader.readingMode"
            ),
            SettingItem(
                type: "switch",
                key: "Reader.skipDuplicateChapters",
                title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS", comment: "")
            ),
            SettingItem(type: "switch", key: "Reader.downsampleImages", title: NSLocalizedString("DOWNSAMPLE_IMAGES", comment: "")),
            SettingItem(type: "switch", key: "Reader.cropBorders", title: NSLocalizedString("CROP_BORDERS", comment: "")),
            SettingItem(type: "switch", key: "Reader.saveImageOption", title: NSLocalizedString("SAVE_IMAGE_OPTION", comment: "")),
            SettingItem(
                type: "select",
                key: "Reader.backgroundColor",
                title: NSLocalizedString("READER_BG_COLOR", comment: ""),
                values: ["system", "white", "black"],
                titles: [
                    NSLocalizedString("READER_BG_COLOR_SYSTEM", comment: ""),
                    NSLocalizedString("READER_BG_COLOR_WHITE", comment: ""),
                    NSLocalizedString("READER_BG_COLOR_BLACK", comment: "")
                ]
            )
        ])])
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

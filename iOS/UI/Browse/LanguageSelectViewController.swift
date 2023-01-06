//
//  LanguageSelectViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/23/22.
//

import UIKit

class LanguageSelectViewController: SettingSelectViewController {

    var languageCodes = Array(SourceManager.languageCodes.dropFirst()) // remove "multi"

    init() {
        // sort alphabetically
        languageCodes.sort(by: {
            let lhs = (Locale.current as NSLocale).displayName(forKey: .identifier, value: $0)
            let rhs = (Locale.current as NSLocale).displayName(forKey: .identifier, value: $1)
            return lhs ?? "" < rhs ?? ""
        })

        // bring local language to top
        languageCodes.removeAll { $0 == Locale.current.languageCode }
        if let code = Locale.current.languageCode {
            languageCodes.insert(code, at: 0)
        }

        var titles = languageCodes.map { (Locale.current as NSLocale).displayName(forKey: .identifier, value: $0) ?? "" }

        languageCodes.insert("multi", at: 0)
        titles.insert(NSLocalizedString("MULTI_LANGUAGE", comment: ""), at: 0)

        super.init(item: SettingItem(
            type: "multi-select",
            key: "Browse.languages",
            title: NSLocalizedString("LANGUAGES", comment: ""),
            footer: "The external source list will be filtered to display only sources for the selected language(s).",
            values: languageCodes,
            titles: titles
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.prefersLargeTitles = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
    }

    @objc func close() {
        dismiss(animated: true)
    }
}

//
//  SettingsAboutViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit

class SettingsAboutViewController: UITableViewController {

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ABOUT", comment: "")

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
    }
}

// MARK: - Table View Data Source
extension SettingsAboutViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "AboutCell")
        if cell == nil {
            cell = UITableViewCell(style: .value1, reuseIdentifier: "AboutCell")
        }

        switch indexPath.row {
        case 0:
            cell?.textLabel?.text = NSLocalizedString("VERSION", comment: "")
            cell?.detailTextLabel?.text = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                                            ?? NSLocalizedString("UNKNOWN", comment: "")
        case 1:
            cell?.textLabel?.text = NSLocalizedString("BUILD", comment: "")
            cell?.detailTextLabel?.text = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                                            ?? NSLocalizedString("UNKNOWN", comment: "")
        default: break
        }
        cell?.detailTextLabel?.textColor = .secondaryLabel
        cell?.selectionStyle = .none

        return cell ?? UITableViewCell()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

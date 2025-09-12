//
//  SettingsTableViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/27/22.
//

import UIKit
import SafariServices
import LocalAuthentication
import AuthenticationServices

class SettingsTableViewController: UITableViewController {

    var items: [SettingItem]
    var source: Source?

    var requireObservers: [SettingItem] = []

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func addObserver(forName name: String, object: Any? = nil, using block: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name(name), object: object, queue: nil, using: block
        ))
    }

    init(items: [SettingItem] = [], source: Source? = nil, style: UITableView.Style = .insetGrouped) {
        self.items = items
        self.source = source
        super.init(style: style)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS", comment: "")
        navigationController?.navigationBar.prefersLargeTitles = true

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
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

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        items[section].footer
    }

    // MARK: Switch Cell
    func switchCell(for item: SettingItem) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UITableViewCell.Subtitle")

        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.textColor = .secondaryLabel
        let switchView = UISwitch()
        switchView.defaultsKey = item.key ?? ""
        switchView.handleChange { isOn in
            if item.authToDisable ?? false && !isOn {
                let context = LAContext()
                if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                    context.evaluatePolicy(
                        .deviceOwnerAuthenticationWithBiometrics,
                        localizedReason: NSLocalizedString("AUTH_TO_DISABLE", comment: "")
                    ) { success, _ in
                        if !success {
                            Task { @MainActor in
                                switchView.setOn(true, animated: true)
                                switchView.sendActions(for: .valueChanged)
                            }
                        }
                    }
                }
            }
            if let notification = item.notification {
                self.source?.performAction(key: notification)
                NotificationCenter.default.post(name: NSNotification.Name(notification), object: item)
            }
        }
        if let requires = item.requires {
            switchView.isEnabled = UserDefaults.standard.bool(forKey: requires)
            observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                Task { @MainActor in
                    switchView.isEnabled = UserDefaults.standard.bool(forKey: requires)
                }
            })
            requireObservers.append(item)
        } else if let requires = item.requiresFalse {
            switchView.isEnabled = !UserDefaults.standard.bool(forKey: requires)
            observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                Task { @MainActor in
                    switchView.isEnabled = !UserDefaults.standard.bool(forKey: requires)
                }
            })
            requireObservers.append(item)
        } else {
            switchView.isEnabled = true
        }
        cell.accessoryView = switchView
        cell.selectionStyle = .none

        return cell
    }

    // MARK: Stepper Cell
    func stepperCell(for item: SettingItem) -> UITableViewCell {
        let cell = StepperTableViewCell(style: .default, reuseIdentifier: "StepperCell")

        cell.titleLabel.text = item.title
        cell.detailLabel.text = String(UserDefaults.standard.integer(forKey: item.key ?? ""))

        let stepperView = cell.stepperView
        if let max = item.maximumValue {
            stepperView.maximumValue = max
        }
        if let min = item.minimumValue {
            stepperView.minimumValue = min
        }
        stepperView.stepValue = item.stepValue ?? 1
        stepperView.defaultsKey = item.key ?? ""
        stepperView.handleChange { _ in
            cell.detailLabel.text = String(UserDefaults.standard.integer(forKey: item.key ?? ""))
            if let notification = item.notification {
                self.source?.performAction(key: notification)
                NotificationCenter.default.post(name: NSNotification.Name(notification), object: item)
            }
        }
        if let requires = item.requires {
            stepperView.isEnabled = UserDefaults.standard.bool(forKey: requires)
            NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                Task { @MainActor in
                    stepperView.isEnabled = UserDefaults.standard.bool(forKey: requires)
                }
            }
            requireObservers.append(item)
        } else if let requires = item.requiresFalse {
            stepperView.isEnabled = !UserDefaults.standard.bool(forKey: requires)
            NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                Task { @MainActor in
                    stepperView.isEnabled = !UserDefaults.standard.bool(forKey: requires)
                }
            }
            requireObservers.append(item)
        } else {
            stepperView.isEnabled = true
        }

        return cell
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath,
        settingItem item: SettingItem
    ) -> UITableViewCell {
        let cell: UITableViewCell
        switch item.type {
        case "select":
            cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            cell.textLabel?.textColor = .label
            cell.accessoryType = .disclosureIndicator

            if let key = item.key {
                if let value = UserDefaults.standard.string(forKey: key),
                   let index = item.values?.firstIndex(of: value) {
                    cell.detailTextLabel?.text = item.titles?[index] ?? item.values?[index]
                }
                observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(key), object: nil, queue: nil) { _ in
                    if let value = UserDefaults.standard.string(forKey: key),
                       let index = item.values?.firstIndex(of: value) {
                        cell.detailTextLabel?.text = item.titles?[index] ?? item.values?[index]
                    }
                })
            }

            if let requires = item.requires {
                cell.textLabel?.textColor = UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                cell.selectionStyle = UserDefaults.standard.bool(forKey: requires) ? .default : .none
                observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                    Task { @MainActor in
                        cell.textLabel?.textColor = UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                        cell.selectionStyle = UserDefaults.standard.bool(forKey: requires) ? .default : .none
                    }
                })
                requireObservers.append(item)
            } else if let requires = item.requiresFalse {
                cell.textLabel?.textColor = !UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                cell.selectionStyle = !UserDefaults.standard.bool(forKey: requires) ? .default : .none
                observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                    Task { @MainActor in
                        cell.textLabel?.textColor = !UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                        cell.selectionStyle = !UserDefaults.standard.bool(forKey: requires) ? .default : .none
                    }
                })
                requireObservers.append(item)
            } else {
                cell.selectionStyle = .default
            }

        case "multi-select", "multi-single-select", "page":
            cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            cell.textLabel?.textColor = .label
            cell.accessoryType = .disclosureIndicator

            if item.type == "multi-single-select", let key = item.key {
                if let value = UserDefaults.standard.stringArray(forKey: item.key ?? "")?.first,
                   let index = item.values?.firstIndex(of: value) {
                    cell.detailTextLabel?.text = item.titles?[index] ?? item.values?[index]
                }
                observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(key), object: nil, queue: nil) { _ in
                    if let value = UserDefaults.standard.stringArray(forKey: item.key ?? "")?.first,
                       let index = item.values?.firstIndex(of: value) {
                        cell.detailTextLabel?.text = item.titles?[index] ?? item.values?[index]
                    }
                })
            }

            if let requires = item.requires {
                cell.textLabel?.textColor = UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                cell.selectionStyle = UserDefaults.standard.bool(forKey: requires) ? .default : .none
                observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                    Task { @MainActor in
                        cell.textLabel?.textColor = UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                        cell.selectionStyle = UserDefaults.standard.bool(forKey: requires) ? .default : .none
                    }
                })
                requireObservers.append(item)
            } else if let requires = item.requiresFalse {
                cell.textLabel?.textColor = !UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                cell.selectionStyle = !UserDefaults.standard.bool(forKey: requires) ? .default : .none
                observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name(requires), object: nil, queue: nil) { _ in
                    Task { @MainActor in
                        cell.textLabel?.textColor = !UserDefaults.standard.bool(forKey: requires) ? .label : .secondaryLabel
                        cell.selectionStyle = !UserDefaults.standard.bool(forKey: requires) ? .default : .none
                    }
                })
                requireObservers.append(item)
            } else {
                cell.selectionStyle = .default
            }

        case "switch":
            cell = switchCell(for: item)

        case "stepper":
            cell = stepperCell(for: item)

        case "button", "link":
            cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            if item.destructive ?? false {
                cell.textLabel?.textColor = .systemRed
            } else {
                cell.textLabel?.textColor = view.tintColor
            }
            cell.accessoryType = .none

        case "login":
            cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            cell.textLabel?.textColor = view.tintColor
            cell.accessoryType = UserDefaults.standard.string(forKey: item.key ?? "") != nil ? .checkmark : .none
            cell.textLabel?.text = UserDefaults.standard.string(forKey: item.key ?? "") != nil ? (item.logoutTitle ?? item.title) : item.title
            return cell

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

    func performAction(for item: SettingItem, at indexPath: IndexPath) {
        switch item.type {
        case "select", "multi-select", "multi-single-select":
            if let requires = item.requires, !UserDefaults.standard.bool(forKey: requires) { return }
            if let requiresFalse = item.requiresFalse, UserDefaults.standard.bool(forKey: requiresFalse) { return }

            if item.authToOpen ?? false {
                let context = LAContext()
                if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                    context.evaluatePolicy(
                        .deviceOwnerAuthenticationWithBiometrics,
                        localizedReason: NSLocalizedString("AUTH_TO_OPEN", comment: "")
                    ) { success, _ in
                        if success {
                            Task { @MainActor in
                                self.navigationController?.pushViewController(
                                    SettingSelectViewController(source: self.source, item: item, style: self.tableView.style),
                                    animated: true
                                )
                            }
                        }
                    }
                }
            } else {
                navigationController?.pushViewController(
                    SettingSelectViewController(source: source, item: item, style: tableView.style),
                    animated: true
                )
            }
        case "link":
            guard
                let url = URL(string: item.url ?? item.key ?? ""),
                url.scheme == "http" || url.scheme == "https"
            else { return }
            if let notification = item.notification {
                self.source?.performAction(key: notification)
                NotificationCenter.default.post(name: NSNotification.Name(notification), object: nil)
            }
            if let external = item.external, external {
                UIApplication.shared.open(url)
            } else {
                let safariViewController = SFSafariViewController(url: url)
                present(safariViewController, animated: true)
            }
        case "button":
            guard let action = item.action else { return }
            source?.performAction(key: action)
            NotificationCenter.default.post(name: NSNotification.Name(action), object: nil)
        case "login":
            guard item.method == "oauth", let key = item.key else { return }
            let url: URL?
            if item.urlKey != nil, let urlString = UserDefaults.standard.string(forKey: item.urlKey ?? "") {
                url = URL(string: urlString)
            } else {
                url = URL(string: item.url ?? "")
            }
            guard let url = url else { return }
            if UserDefaults.standard.string(forKey: key) != nil { // log out
                UserDefaults.standard.set(nil, forKey: key)
                if let notification = item.notification {
                    source?.performAction(key: notification)
                    NotificationCenter.default.post(name: NSNotification.Name(notification), object: nil)
                }
                self.tableView.cellForRow(at: indexPath)?.accessoryType = .none
                self.tableView.cellForRow(at: indexPath)?.textLabel?.text = item.title
            } else { // log in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aidoku") { callbackURL, error in
                    if let error = error {
                        let sourceInfoString = self.source != nil ? " for \(self.source?.manifest.info.name ?? "source")" : ""
                        LogManager.logger.error("Log-in authentication error\(sourceInfoString): \(error.localizedDescription)")
                    }
                    if let callbackURL = callbackURL {
                        UserDefaults.standard.set(callbackURL.absoluteString, forKey: key)
                        Task { @MainActor in
                            if let notification = item.notification {
                                self.source?.performAction(key: notification)
                                NotificationCenter.default.post(name: NSNotification.Name(notification), object: nil)
                            }
                            self.tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
                            self.tableView.cellForRow(at: indexPath)?.textLabel?.text = item.logoutTitle ?? item.title
                        }
                    }
                }
                session.presentationContextProvider = self
                session.start()
            }
        case "page":
            guard let items = item.items else { return }
            let subPage = SettingsTableViewController(items: items, source: source, style: tableView.style)
            subPage.title = item.title
            present(subPage, animated: true)
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let item = items[indexPath.section].items?[indexPath.row] {
            performAction(for: item, at: indexPath)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Auth Presentation Provider
extension SettingsTableViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

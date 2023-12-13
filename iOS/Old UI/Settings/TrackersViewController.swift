//
//  TrackersViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/17/22.
//

import UIKit
import AuthenticationServices

class TrackersViewController: UITableViewController {

    var trackers: [Tracker] = []

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("TRACKERS", comment: "")

        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")

        Task { @MainActor in
            trackers = TrackerManager.shared.trackers
            tableView.reloadSections(IndexSet(integer: 0), with: .fade)
        }
    }

    func logout(at indexPath: IndexPath) {
        guard indexPath.row < self.trackers.count else { return }
        let alert = UIAlertController(
            title: String(format: NSLocalizedString("LOGOUT_FROM_%@", comment: ""), self.trackers[indexPath.row].name),
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("LOGOUT", comment: ""), style: .default) { _ in
            guard indexPath.row < self.trackers.count else { return }
            self.trackers[indexPath.row].logout()
            self.tableView.cellForRow(at: indexPath)?.accessoryType = .none
            Task {
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    CoreDataManager.shared.removeTracks(trackerId: self.trackers[indexPath.row].id, context: context)
                    try? context.save()
                }
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("CANCEL", comment: ""), style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - Table View Data Source
extension TrackersViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        trackers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)

        let tracker = trackers[indexPath.row]
        cell.textLabel?.text = tracker.name
        cell.accessoryType = tracker.isLoggedIn ? .checkmark : .none
        cell.imageView?.image = tracker.icon

        // display warning mark if we need to re-login
        if let tracker = tracker as? OAuthTracker {
            if tracker.oauthClient.tokens == nil {
                tracker.oauthClient.loadTokens()
            }
            if tracker.oauthClient.tokens?.askedForRefresh ?? true {
                cell.accessoryType = .none
                let iconView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
                iconView.tintColor = .systemYellow
                iconView.tag = 10 // hack until we make this an actual table cell, so that we can remove it after we log in
                iconView.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(iconView)
                NSLayoutConstraint.activate([
                    iconView.widthAnchor.constraint(equalToConstant: 20),
                    iconView.heightAnchor.constraint(equalToConstant: 20),
                    iconView.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
                    iconView.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor)
                ])
            }
        }

        cell.imageView?.clipsToBounds = true
        cell.imageView?.layer.cornerRadius = 42 * 0.225
        cell.imageView?.layer.cornerCurve = .continuous
        cell.imageView?.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        cell.imageView?.layer.borderWidth = 1
        cell.imageView?.translatesAutoresizingMaskIntoConstraints = false
        cell.textLabel?.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.heightAnchor.constraint(equalToConstant: 58).isActive = true
        cell.imageView?.widthAnchor.constraint(equalToConstant: 42).isActive = true
        cell.imageView?.heightAnchor.constraint(equalToConstant: 42).isActive = true
        cell.imageView?.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor).isActive = true
        cell.imageView?.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        cell.textLabel?.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor).isActive = true
        if cell.imageView != nil {
            cell.textLabel?.leadingAnchor.constraint(equalTo: cell.imageView!.trailingAnchor, constant: 12).isActive = true
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let tracker = trackers[indexPath.row]

        // check if we need to re-login
        var needsRelogin = false
        if let tracker = tracker as? OAuthTracker {
            if tracker.oauthClient.tokens?.askedForRefresh ?? true {
                needsRelogin = true
            }
        }

        guard needsRelogin || !tracker.isLoggedIn else {
            logout(at: indexPath)
            return
        }

        if let tracker = tracker as? OAuthTracker {
            guard let url = URL(string: tracker.authenticationUrl) else { return }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aidoku") { callbackURL, error in
                if let error = error {
                    LogManager.logger.error("Tracker authentication error: \(error.localizedDescription)")
                }
                if let callbackURL = callbackURL {
                    Task { @MainActor in
                        let loadingIndicator = UIActivityIndicatorView(style: .medium)
                        loadingIndicator.startAnimating()
                        let cell = tableView.cellForRow(at: indexPath)
                        cell?.accessoryView = loadingIndicator
                        await tracker.handleAuthenticationCallback(url: callbackURL)
                        cell?.accessoryView = nil
                        if tracker.isLoggedIn {
                            cell?.accessoryType = .checkmark
                            // remove the warning icon we might've added
                            let iconView = cell?.contentView.subviews.first(where: { $0.tag == 10 })
                            iconView?.removeFromSuperview()
                            tracker.oauthClient.loadTokens()
                        } else {
                            cell?.accessoryType = .none
                        }

                        NotificationCenter.default.post(name: Notification.Name("updateTrackers"), object: nil)
                    }
                }
            }
            session.presentationContextProvider = self
            session.start()
        }
    }
}

extension TrackersViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

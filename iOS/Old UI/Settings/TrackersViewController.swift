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

        guard !tracker.isLoggedIn else {
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
                        tableView.cellForRow(at: indexPath)?.accessoryView = loadingIndicator
                        await tracker.handleAuthenticationCallback(url: callbackURL)
                        tableView.cellForRow(at: indexPath)?.accessoryView = nil
                        tableView.cellForRow(at: indexPath)?.accessoryType = tracker.isLoggedIn ? .checkmark : .none
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

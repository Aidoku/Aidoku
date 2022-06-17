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

        Task { @MainActor in
            trackers = TrackerManager.shared.trackers
            tableView.reloadSections(IndexSet(integer: 0), with: .fade)
        }
    }
}

// MARK: - Table View Data Source
extension TrackersViewController {

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        trackers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCellSubtitle")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UITableViewCellSubtitle")
        }
        guard let cell = cell else { return UITableViewCell() }

        let tracker = trackers[indexPath.row]
        cell.textLabel?.text = tracker.name
        cell.detailTextLabel?.text = nil
        cell.accessoryType = tracker.isLoggedIn ? .checkmark : .none

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let tracker = trackers[indexPath.row]

        guard !tracker.isLoggedIn else {
            tracker.logout()
            tableView.cellForRow(at: indexPath)?.accessoryType = .none
            return
        }

        if let tracker = tracker as? OAuthTracker {
            guard let url = URL(string: tracker.authenticationUrl) else { return }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aidoku") { callbackURL, error in
                if let error = error {
                    LogManager.logger.error("Tracker authentication error: \(error.localizedDescription)")
                }
                if let callbackURL = callbackURL {
                    tracker.handleAuthenticationCallback(url: callbackURL)
                    // Assume that the login request succeeds
                    tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
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

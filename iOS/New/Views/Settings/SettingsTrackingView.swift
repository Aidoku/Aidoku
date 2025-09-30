//
//  SettingsTrackingView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import AuthenticationServices
import SwiftUI

struct SettingsTrackingView: View {
    @State private var trackers: [Tracker]

    @State private var loadingTrackerId: String?
    @State private var logoutTrackerName: String?
    @State private var showLogoutAlert = false

    private let iconSize: CGFloat = 42
    private let iconCornerRadius: CGFloat = 42 * 0.225

    // empty view controller to support login view presentation
    private static var loginShimController = LoginShimViewController()

    init() {
        self._trackers = State(initialValue: TrackerManager.shared.trackers.filter { !($0 is EnhancedTracker) })
    }

    var body: some View {
        List {
            Section {
                SettingView(setting: .init(
                    key: "Tracking.updateAfterReading",
                    title: NSLocalizedString("UPDATE_AFTER_READING"),
                    value: .toggle(.init())
                ))
            } footer: {
                Text(NSLocalizedString("UPDATE_AFTER_READING_INFO"))
            }
            Section {
                SettingView(setting: .init(
                    key: "Tracking.autoSyncFromTracker",
                    title: NSLocalizedString("AUTO_SYNC_HISTORY"),
                    value: .toggle(.init())
                ))
            } footer: {
                Text(NSLocalizedString("AUTO_SYNC_HISTORY_INFO"))
            }
            Section(NSLocalizedString("TRACKERS")) {
                ForEach(trackers.indices, id: \.self) { index in
                    let tracker = trackers[index]
                    let needsRelogin = if let tracker = tracker as? OAuthTracker, tracker.oauthClient.tokens?.askedForRefresh == true {
                        true
                    } else {
                        false
                    }
                    Button {
                        if tracker.isLoggedIn && !needsRelogin {
                            logoutTrackerName = tracker.name
                            showLogoutAlert = true
                        } else {
                            login(to: tracker)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = tracker.icon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: iconSize, height: iconSize)
                                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: iconCornerRadius)
                                            .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
                                    )
                            }
                            Text(tracker.name)
                                .foregroundStyle(.primary)
                                .tint(.primary)

                            Spacer()

                            if loadingTrackerId == tracker.id {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else if needsRelogin {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            } else if tracker.isLoggedIn {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("TRACKING"))
        .alert(String(format: NSLocalizedString("LOGOUT_FROM_%@"), logoutTrackerName ?? ""), isPresented: $showLogoutAlert) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("LOGOUT"), role: .destructive) {
                if let name = logoutTrackerName, let tracker = trackers.first(where: { $0.name == name }) {
                    Task {
                        // Call tracker logout to clear authentication data
                        tracker.logout()
                        NotificationCenter.default.post(name: .updateTrackers, object: nil)
                        // Remove all tracked items for this tracker
                        await CoreDataManager.shared.container.performBackgroundTask { context in
                            CoreDataManager.shared.removeTracks(trackerId: tracker.id, context: context)
                            try? context.save()
                        }
                    }
                }
            }
        }
    }
}

extension SettingsTrackingView {
    func login(to tracker: Tracker) {
        if let tracker = tracker as? OAuthTracker {
            guard let url = URL(string: tracker.authenticationUrl) else { return }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aidoku") { callbackURL, error in
                if let error {
                    LogManager.logger.error("Tracker authentication error: \(error.localizedDescription)")
                }
                if let callbackURL {
                    Task { @MainActor in
                        let loadingIndicator = UIActivityIndicatorView(style: .medium)
                        loadingIndicator.startAnimating()

                        loadingTrackerId = tracker.id
                        await tracker.handleAuthenticationCallback(url: callbackURL)
                        loadingTrackerId = nil

                        if tracker.isLoggedIn {
                            tracker.oauthClient.loadTokens()
                        }

                        NotificationCenter.default.post(name: .updateTrackers, object: nil)
                    }
                }
            }
            session.presentationContextProvider = Self.loginShimController
            session.start()
        }
    }
}

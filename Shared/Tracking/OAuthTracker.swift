//
//  OAuthTracker.swift
//  Aidoku
//
//  Created by Skitty on 7/22/22.
//

import Foundation

/// A protocol for trackers that utilize OAuth authentication.
protocol OAuthTracker: Tracker {
    /// The host in the oauth callback url, e.g. `host` in `aidoku://host`.
    var callbackHost: String { get }
    /// The URL used to authenticate with the tracker service provider.
    var authenticationUrl: String { get }
    /// The OAuth access token for the tracker.
    var token: String? { get set }

    var oauthClient: OAuthClient { get }

    /// A callback function called after authenticating.
    func handleAuthenticationCallback(url: URL) async
}

extension OAuthTracker {
    var token: String? {
        get {
            UserDefaults.standard.string(forKey: "Tracker.\(id).token")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Tracker.\(id).token")
        }
    }

    var isLoggedIn: Bool {
        token != nil
    }

    func logout() {
        token = nil
        UserDefaults.standard.removeObject(forKey: "Tracker.\(id).oauth")
        UserDefaults.standard.removeObject(forKey: "Tracker.\(id).token")
    }
}

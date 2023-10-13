//
//  HostUserPasswordTracker.swift
//  Aidoku
//
//  Created by Paolo Casellati on 13/10/23.
//

import Foundation

protocol HostUserPassTracker: Tracker {
    
    var hostname: String? { get set }
    var username: String? { get set }
    var password: String? { get set }

    func login(host: String, user: String, pass: String) async -> Bool
}

extension HostUserPassTracker {
    var hostname: String? {
        get {
            UserDefaults.standard.string(forKey: "Tracker.\(id).hostname")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Tracker.\(id).hostname")
        }
    }
    
    var username: String? {
        get {
            UserDefaults.standard.string(forKey: "Tracker.\(id).username")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Tracker.\(id).username")
        }
    }
    
    var password: String? {
        get {
            UserDefaults.standard.string(forKey: "Tracker.\(id).password")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "Tracker.\(id).password")
        }
    }

    var isLoggedIn: Bool {
        username != nil && password != nil && hostname != nil
    }
    
    func logout() {
        self.hostname = nil
        self.username = nil
        self.password = nil

        UserDefaults.standard.removeObject(forKey: "Tracker.\(id).hostname")
        UserDefaults.standard.removeObject(forKey: "Tracker.\(id).username")
        UserDefaults.standard.removeObject(forKey: "Tracker.\(id).password")
    }
}

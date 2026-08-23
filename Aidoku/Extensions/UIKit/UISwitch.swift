//
//  UISwitch.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit

extension UISwitch {
    private static var _defaultsKey = [String: String?]()
    private static var _handlers = [String: (Bool) -> Void]()

    var defaultsKey: String? {
        get {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            return Self._defaultsKey[tmpAddress] ?? nil
        }
        set {
            let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
            Self._defaultsKey[tmpAddress] = newValue
            addTarget(self, action: #selector(toggleDefaultsSetting), for: .valueChanged)
            if let key = newValue {
                isOn = UserDefaults.standard.bool(forKey: key)
            } else {
                isOn = false
            }
            addTarget(self, action: #selector(notifyHandler), for: .valueChanged)
        }
    }

    @objc func handleChange(_ handler: @escaping (Bool) -> Void) {
        let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
        Self._handlers[tmpAddress] = handler
    }

    @objc func toggleDefaultsSetting() {
        if let key = defaultsKey {
            UserDefaults.standard.set(isOn, forKey: key)
        }
    }

    @objc func notifyHandler() {
        let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
        if let handler = Self._handlers[tmpAddress] {
            handler(isOn)
        }
        if let key = defaultsKey {
            NotificationCenter.default.post(name: NSNotification.Name(key), object: isOn)
        }
    }
}

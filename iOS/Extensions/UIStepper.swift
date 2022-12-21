//
//  UIStepper.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 4/21/22.
//

import UIKit

extension UIStepper {
    private static var _defaultsKey = [String: String?]()
    private static var _handlers = [String: (Double) -> Void]()

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
                value = UserDefaults.standard.double(forKey: key)
            } else {
                value = 0
            }
            addTarget(self, action: #selector(notifyHandler), for: .valueChanged)
        }
    }

    @objc func handleChange(_ handler: @escaping (Double) -> Void) {
        let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
        Self._handlers[tmpAddress] = handler
    }

    @objc func toggleDefaultsSetting() {
        guard let key = defaultsKey else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    @objc func notifyHandler() {
        let tmpAddress = String(format: "%p", unsafeBitCast(self, to: Int.self))
        if let handler = Self._handlers[tmpAddress] {
            handler(value)
        }
        if let key = defaultsKey {
            NotificationCenter.default.post(name: NSNotification.Name(key), object: value)
        }
    }
}

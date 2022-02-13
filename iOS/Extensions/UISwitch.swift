//
//  UISwitch.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit

extension UISwitch {
    private static var _defaultsKey = [String: String?]()
    
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
        }
    }
    
    @objc func toggleDefaultsSetting() {
        if let key = defaultsKey {
            UserDefaults.standard.set(isOn, forKey: key)
        }
    }
}

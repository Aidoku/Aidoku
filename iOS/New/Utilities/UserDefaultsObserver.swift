//
//  UserDefaultsObserver.swift
//  Aidoku
//
//  Created by Skitty on 5/5/25.
//

import Combine
import SwiftUI

class UserDefaultsObserver: ObservableObject {
    @Published var observedValues: [String: Any?] = [:]

    private var cancellable: AnyCancellable?

    init(keys: [String]) {
        var observedValues: [String: Any?] = [:]
        for key in keys {
            let value = UserDefaults.standard.object(forKey: key)
            observedValues[key] = value
        }
        self.observedValues = observedValues

        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    for key in keys where !key.isEmpty {
                        let newValue = UserDefaults.standard.object(forKey: key)
                        let oldValue = self.observedValues[key, default: nil]
                        if !Self.isEqual(oldValue, newValue) {
                            self.observedValues[key] = newValue
                        }
                    }
                }
            }
    }

    convenience init(key: String) {
        self.init(keys: [key])
    }

    private static func isEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if let lhs = lhs as? NSObject, let rhs = rhs as? NSObject {
            return lhs == rhs
        } else {
            return lhs == nil && rhs == nil
        }
    }
}

class UserDefaultsBool: ObservableObject {
    @Published var value: Bool {
        didSet {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private let key: String
    private var cancellable: AnyCancellable?

    init(key: String, defaultValue: Bool = false) {
        self.key = key
        self.value = UserDefaults.standard.bool(forKey: key)

        cancellable = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                let newValue = UserDefaults.standard.bool(forKey: self.key)
                if self.value != newValue {
                    self.value = newValue
                }
            }
    }
}

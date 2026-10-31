//
//  UIButton.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 9/3/26.
//

import UIKit

extension UIButton.Configuration {
    // the reader's floating buttons: glass on iOS 26, a filled circle before it
    static func glassCapsule() -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = .secondarySystemBackground
            configuration.baseForegroundColor = .label
        }
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(top: 10, leading: 10, bottom: 10, trailing: 10)
        return configuration
    }
}

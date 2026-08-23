//
//  UIApplication.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import UIKit

extension UIApplication {
    var firstKeyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .keyWindow
    }
}

//
//  UIViewController+Alerts.swift
//  Aidoku (iOS)
//
//  Created by Mihajlo Saric on 6.5.24..
//

import Foundation
import UIKit

extension UIViewController {
    func presentAlert(title: String, message: String, actions: [UIAlertAction] = [], completion: (() -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        // If no actions are provided, add a default 'OK' action
        if actions.isEmpty {
            let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default)
            alertController.addAction(okAction)
        } else {
            for action in actions {
                alertController.addAction(action)
            }
        }

        self.present(alertController, animated: true, completion: completion)
    }
}

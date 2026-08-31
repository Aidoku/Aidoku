//
//  UIViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import SwiftUI

extension UIViewController {
    func add(child: UIViewController, below: UIView? = nil) {
        addChild(child)
        if let below {
            view.insertSubview(child.view, belowSubview: below)
        } else {
            view.addSubview(child.view)
        }
        child.didMove(toParent: self)
    }

    func remove() {
        guard parent != nil else {
            return
        }
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }

    func presentAlert(title: String, message: String, actions: [UIAlertAction] = [], completion: (() -> Void)? = nil) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        // If no actions are provided, add a default 'OK' action
        if actions.isEmpty {
            let okAction = UIAlertAction(title: NSLocalizedString("OK"), style: .cancel)
            alertController.addAction(okAction)
        } else {
            for action in actions {
                alertController.addAction(action)
            }
        }

        self.present(alertController, animated: true, completion: completion)
    }
}

private protocol AnyUIHostingViewController: AnyObject {}
extension UIHostingController: AnyUIHostingViewController {}

extension UIViewController {
    /// Checks if this UIViewController is wrapped inside of SwiftUI. Must be used after viewDidLoad
    var isWrapped: Bool { parent is AnyUIHostingViewController }
}

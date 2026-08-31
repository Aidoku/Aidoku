//
//  UINavigationController+DismissGestures.swift
//  Aidoku
//
//  Created by Skitty on 12/22/25.
//

import UIKit

extension UINavigationController {
    func setDismissGesturesEnabled(_ isEnabled: Bool) {
        let gestureRecognizers = (view.gestureRecognizers ?? []) + (topViewController?.view.gestureRecognizers ?? [])

        for recognizer in gestureRecognizers {
            switch String(describing: type(of: recognizer)) {
                case "_UIParallaxTransitionPanGestureRecognizer": // swipe edge gesture
                    recognizer.isEnabled = isEnabled

                case "_UIContentSwipeDismissGestureRecognizer": // swipe down gesture
                    recognizer.isEnabled = isEnabled

                case "_UITransformGestureRecognizer": // pinch gesture
                    recognizer.isEnabled = isEnabled

                default:
                    break
            }
        }
    }
}

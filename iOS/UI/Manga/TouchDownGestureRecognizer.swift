//
//  TouchDownGestureRecognizer.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/26/23.
//

import UIKit

class TouchDownGestureRecognizer: UIGestureRecognizer {
    private var startPoint: CGPoint?

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .began
        startPoint = location(in: view)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        state = .changed

        // cancel gesture if we start scrolling
        guard let startPoint else { return }
        let position = location(in: view)
        if abs(position.y - startPoint.y) >= 10 {
            state = .cancelled
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }
}

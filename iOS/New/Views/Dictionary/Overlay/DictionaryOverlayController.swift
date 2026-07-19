//
//  DictionaryOverlayController.swift
//  Aidoku
//
//  Created by skitty on 7/19/26.
//

import CHoshiDicts
import CxxStdlib
import UIKit

enum DictionaryOverlayInteractionMode {
    case none
    case singleTap
    case longPress
}

final class DictionaryOverlayController: NSObject {
    weak var containerView: UIView?
    var onLookup: ((String, CGRect, [CGRect]) -> Void)?
    var interactionMode: DictionaryOverlayInteractionMode = .none

    private weak var activeButton: DictionaryOverlayButton?

    @available(iOS 18.0, *)
    func render(overlays: [TextRecognizer.ParagraphOverlay]) {
        clear()
        guard let containerView else { return }

        for overlay in overlays {
            let button = DictionaryOverlayButton(type: .system)
            button.apply(overlay: overlay)
            button.setOverlayVisible(false)
            applyInteractionMode(to: button)
            containerView.addSubview(button)
        }
    }

    func clear() {
        guard let containerView else {
            activeButton = nil
            return
        }
        for case let overlay as DictionaryOverlayButton in containerView.subviews {
            overlay.removeFromSuperview()
        }
        activeButton = nil
    }

    func activateOverlay(at point: CGPoint) -> Bool {
        guard let button = overlayButton(at: point) else {
            setActiveButton(nil)
            return false
        }
        setActiveButton(button)
        return true
    }

    // swiftlint:disable:next large_tuple
    func lookupPayload(at point: CGPoint) -> (text: String, rect: CGRect, charRects: [CGRect])? {
        guard let button = overlayButton(at: point) else { return nil }
        setActiveButton(button)

        let localPoint = containerView?.convert(point, to: button) ?? CGPoint(
            x: button.bounds.midX,
            y: button.bounds.midY
        )
        guard let payload = button.lookupPayload(at: localPoint) else { return nil }

        let anchorRect = payload.localRect.offsetBy(dx: button.frame.minX, dy: button.frame.minY)
        let charRects = payload.localRects.map { $0.offsetBy(dx: button.frame.minX, dy: button.frame.minY) }
        return (payload.text, anchorRect, charRects)
    }

    @discardableResult
    func dismissActive() -> Bool {
        guard activeButton != nil else { return false }
        setActiveButton(nil)
        return true
    }

    private func setActiveButton(_ button: DictionaryOverlayButton?) {
        activeButton = button
        guard let containerView else { return }
        for case let overlay as DictionaryOverlayButton in containerView.subviews {
            overlay.setOverlayVisible(overlay === button)
        }
        if let button {
            containerView.bringSubviewToFront(button)
        }
    }

    private func overlayButton(at point: CGPoint) -> DictionaryOverlayButton? {
        guard let containerView else { return nil }
        let localPoint = containerView.convert(point, to: containerView)
        for subview in containerView.subviews.reversed() {
            guard let button = subview as? DictionaryOverlayButton else { continue }
            let pointInButton = containerView.convert(localPoint, to: button)
            if button.bounds.contains(pointInButton) {
                return button
            }
        }
        return nil
    }

    private func applyInteractionMode(to button: DictionaryOverlayButton) {
        button.removeTarget(nil, action: nil, for: .allEvents)
        button.gestureRecognizers?.forEach { button.removeGestureRecognizer($0) }

        switch interactionMode {
            case .singleTap:
                button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDown)
                button.addTarget(self, action: #selector(handleTouchDown(_:)), for: .touchDragEnter)
                button.addTarget(self, action: #selector(handleTouchCancel(_:)), for: .touchUpOutside)
                button.addTarget(self, action: #selector(handleTouchCancel(_:)), for: .touchCancel)
                button.addTarget(self, action: #selector(handleTouchCancel(_:)), for: .touchDragExit)
                button.addTarget(self, action: #selector(handleTouchUpInside(_:for:)), for: .touchUpInside)
            case .longPress:
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
                longPress.minimumPressDuration = 0.25
                longPress.allowableMovement = 60
                longPress.cancelsTouchesInView = true
                button.addGestureRecognizer(longPress)
            case .none:
                break
        }
    }

    @objc
    private func handleTouchDown(_ sender: DictionaryOverlayButton) {
        setActiveButton(sender)
    }

    @objc
    private func handleTouchCancel(_ sender: DictionaryOverlayButton) {
        if activeButton === sender {
            setActiveButton(nil)
        }
    }

    @objc
    private func handleTouchUpInside(_ sender: DictionaryOverlayButton, for event: UIEvent) {
        let touch = event.touches(for: sender)?.first ?? event.allTouches?.first
        let point = touch?.location(in: sender) ?? CGPoint(x: sender.bounds.midX, y: sender.bounds.midY)
        performLookup(sender: sender, point: point)
    }

    @objc
    private func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard let sender = gestureRecognizer.view as? DictionaryOverlayButton else { return }
        let point = gestureRecognizer.location(in: sender)
        switch gestureRecognizer.state {
        case .began, .changed:
            setActiveButton(sender)
        case .ended:
            performLookup(sender: sender, point: point)
        default:
            if activeButton === sender {
                setActiveButton(nil)
            }
        }
    }

    private func performLookup(sender: DictionaryOverlayButton, point: CGPoint) {
        setActiveButton(sender)
        guard let payload = sender.lookupPayload(at: point) else { return }
        let anchorRect = payload.localRect.offsetBy(dx: sender.frame.minX, dy: sender.frame.minY)
        let charRects = payload.localRects.map { $0.offsetBy(dx: sender.frame.minX, dy: sender.frame.minY) }
        onLookup?(payload.text, anchorRect, charRects)
    }
}

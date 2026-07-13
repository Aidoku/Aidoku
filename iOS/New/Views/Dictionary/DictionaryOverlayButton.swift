//
//  DictionaryOverlayButton.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CHoshiDicts
import UIKit

enum DictionaryOverlayInteractionMode {
    case none
    case singleTap
    case longPress
}

final class DictionaryOverlayPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}

final class DictionaryOverlayButton: UIButton {
    struct LookupHit {
        let text: String
        let localRect: CGRect
        let localRects: [CGRect]
    }

    struct LookupPayload {
        let text: String
        let localRect: CGRect
        let localRects: [CGRect]
    }

    private struct LocalCharHit {
        let text: String
        let rect: CGRect
    }

    var overlayText: String = ""

    private var localCharHits: [LocalCharHit] = []
    private var renderedSegmentLabels: [UILabel] = []

    @available(iOS 18.0, *)
    func apply(overlay: TextRecognizer.ParagraphOverlay) {
        overlayText = overlay.text
        frame = overlay.rect
        layer.cornerRadius = 4
        clipsToBounds = true
        configureLabelsAndHits(for: overlay)
    }

    func setOverlayVisible(_ visible: Bool) {
        if visible {
            backgroundColor = .white.withAlphaComponent(0.92)
            layer.borderColor = UIColor.black.cgColor
            layer.borderWidth = 1
            setTitleColor(.black, for: .normal)
            setTitleColor(.black, for: .highlighted)
            setTitleColor(.black, for: .selected)
            setTitleColor(.black, for: .focused)
            renderedSegmentLabels.forEach { $0.textColor = .black }
        } else {
            backgroundColor = .clear
            layer.borderColor = UIColor.clear.cgColor
            layer.borderWidth = 0
            setTitleColor(.clear, for: .normal)
            setTitleColor(.clear, for: .highlighted)
            setTitleColor(.clear, for: .selected)
            setTitleColor(.clear, for: .focused)
            renderedSegmentLabels.forEach { $0.textColor = .clear }
        }
    }

    func lookupHit(at localPoint: CGPoint) -> LookupHit? {
        guard let index = localCharHits.firstIndex(where: { $0.rect.contains(localPoint) }) else { return nil }
        let hit = localCharHits[index]
        let rects = Array(localCharHits[index...].map(\.rect))
        return .init(text: hit.text, localRect: hit.rect, localRects: rects)
    }

    func lookupPayload(at localPoint: CGPoint) -> LookupPayload? {
        guard let hit = lookupHit(at: localPoint) else { return nil }
        let matchedText = resolveMatchedText(from: hit.text)
        let matchLength = max(1, matchedText.count)
        let localRects = Array(hit.localRects.prefix(matchLength))
        return .init(text: matchedText, localRect: hit.localRect, localRects: localRects)
    }

    @available(iOS 18.0, *)
    private func configureLabelsAndHits(for overlay: TextRecognizer.ParagraphOverlay) {
        renderedSegmentLabels.forEach { $0.removeFromSuperview() }
        renderedSegmentLabels.removeAll()
        localCharHits.removeAll()

        let storedScale = CGFloat(UserDefaults.standard.double(forKey: "Dictionary.overlayTextScaleMultiplier"))
        let textScaleMultiplier = max(0.5, min(1.25, storedScale > 0 ? storedScale : 1))
        let storedPadding = CGFloat(UserDefaults.standard.double(forKey: "Dictionary.overlayPadding"))
        let labelPadding = max(0, min(10, storedPadding > 0 ? storedPadding : 5))

        for segment in overlay.segments {
            let localRect = CGRect(
                x: segment.rect.minX - overlay.rect.minX,
                y: segment.rect.minY - overlay.rect.minY,
                width: segment.rect.width,
                height: segment.rect.height
            ).intersection(bounds)
            guard localRect.width > 3, localRect.height > 3 else { continue }

            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let isVertical = localRect.height > localRect.width * 1.2
            let displayText = isVertical ? text.map(String.init).joined(separator: "\n") : text
            let glyphCount = max(text.count, 1)
            let fontSize: CGFloat = if isVertical {
                max(8, min(localRect.width * 0.72, localRect.height / CGFloat(glyphCount) * 0.88)) * textScaleMultiplier
            } else {
                max(8, min(localRect.height * 0.72, 24)) * textScaleMultiplier
            }

            let horizontalPadding = isVertical ? CGFloat(0) : labelPadding
            let verticalPadding = labelPadding
            let labelFrame = localRect.insetBy(dx: -horizontalPadding, dy: -verticalPadding).intersection(bounds)
            guard labelFrame.width > 2, labelFrame.height > 2 else { continue }
            let label = UILabel(frame: labelFrame)
            label.isUserInteractionEnabled = false
            label.backgroundColor = .clear
            label.font = .systemFont(ofSize: fontSize, weight: .regular)
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            label.textAlignment = isVertical ? .center : .left
            label.text = displayText
            label.textColor = .clear
            addSubview(label)
            renderedSegmentLabels.append(label)
            localCharHits.append(contentsOf: renderedCharHits(
                in: label,
                displayText: displayText,
                sourceHits: segment.charHits
            ))
        }
    }

    @available(iOS 18.0, *)
    private func renderedCharHits(
        in label: UILabel,
        displayText: String,
        sourceHits: [TextRecognizer.ParagraphOverlay.CharHit]
    ) -> [LocalCharHit] {
        guard let font = label.font, !displayText.isEmpty else { return [] }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = label.textAlignment
        paragraph.lineBreakMode = label.lineBreakMode

        let storage = NSTextStorage(
            string: displayText,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: label.bounds.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = label.numberOfLines
        container.lineBreakMode = label.lineBreakMode
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)

        let nsDisplay = displayText as NSString
        var sourceIndex = 0
        var hits: [LocalCharHit] = []

        for displayIndex in 0..<nsDisplay.length {
            if sourceIndex >= sourceHits.count { break }

            let char = nsDisplay.substring(with: NSRange(location: displayIndex, length: 1))
            if char == "\n" || char == "\r" {
                continue
            }

            let charRange = NSRange(location: displayIndex, length: 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            if rect.isNull || rect.isEmpty { continue }

            rect.origin.x += label.frame.minX
            rect.origin.y += label.frame.minY
            rect = rect.insetBy(dx: -1, dy: -1).intersection(bounds)
            guard rect.width > 0, rect.height > 0 else { continue }

            hits.append(.init(text: sourceHits[sourceIndex].text, rect: rect))
            sourceIndex += 1
        }

        return hits
    }

    private func resolveMatchedText(from text: String) -> String {
        guard #available(iOS 18.0, *), let first = LookupEngine.shared.lookup(text).first else { return text }

        let matched = String(first.matched)
        let expression = String(first.term.expression)
        let reading = String(first.term.reading)

        var candidates: [Int] = []

        if !matched.isEmpty, text.hasPrefix(matched) {
            candidates.append(matched.count)
        }
        if !expression.isEmpty, text.hasPrefix(expression) {
            candidates.append(expression.count)
        }
        if !reading.isEmpty, text.hasPrefix(reading) {
            candidates.append(reading.count)
        }

        let fallback = min(matched.count, text.count)
        let matchLength = max(1, candidates.min() ?? max(1, fallback))
        return String(text.prefix(matchLength))
    }
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

//
//  DictionaryOverlayButton.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import CHoshiDicts
import CxxStdlib
import UIKit

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

        let storedScale = CGFloat(AppSettings.dictionary.overlayTextScaleMultiplier.get())
        let textScaleMultiplier = max(0.5, min(1.25, storedScale > 0 ? storedScale : 1))
        let storedPadding = CGFloat(AppSettings.dictionary.overlayPadding.get())
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

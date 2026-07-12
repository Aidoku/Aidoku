//
//  ReaderDictionaryCoordinator.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI
import UIKit

final class ReaderDictionaryCoordinator {
    private struct PopupController {
        let id: UUID
        let controller: UIViewController
    }

    private weak var owner: ReaderViewController?
    private var popupControllers: [PopupController] = []
    private var lookupHighlightViews: [UIView] = []
    private weak var selectionHighlightView: UIView?
    private var cachedSelectionMatch: (text: String, matchedCount: Int?)?

    var isPopupVisible: Bool {
        !popupControllers.isEmpty
    }

    init(owner: ReaderViewController) {
        self.owner = owner
    }

    @available(iOS 18.0, *)
    @discardableResult
    func performLookup(
        text: String,
        anchorRect: CGRect,
        charRects: [CGRect] = [],
        appendPopup: Bool = false
    ) -> Bool {
        guard let owner else { return false }

        let entries = LookupEngine.shared.lookup(text)
        guard !entries.isEmpty else { return false }

        if !appendPopup {
            dismissAllPopups()
            addLookupHighlight(for: entries, charRects: charRects)
        }

        let popupID = UUID()
        let styles = LookupEngine.shared.getStyles()
        let availableFrame = owner.barsHidden
            ? owner.view.bounds
            : owner.view.safeAreaLayoutGuide.layoutFrame
        let popupView = DictionaryPopupView(
            entries: entries,
            dictionaryStyles: styles,
            anchorRect: anchorRect,
            availableFrame: availableFrame,
            onLookup: { [weak self] selection in
                guard let self else { return }
                _ = self.performLookup(
                    text: selection.text,
                    anchorRect: selection.rect ?? anchorRect,
                    appendPopup: true
                )
            },
            onDismiss: { [weak self] in
                self?.dismissTopPopup()
            },
            onTapOutside: { [weak self] in
                self?.dismissChildPopups(parentID: popupID)
            }
        )

        let hostingController = UIHostingController(rootView: popupView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        owner.add(child: hostingController)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: owner.view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: owner.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: owner.view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: owner.view.bottomAnchor)
        ])

        popupControllers.append(PopupController(id: popupID, controller: hostingController))
        return true
    }

    func dismissTopPopup() {
        guard let popup = popupControllers.popLast() else { return }
        let controller = popup.controller
        controller.view.removeFromSuperview()
        controller.removeFromParent()

        if popupControllers.isEmpty {
            clearLookupHighlights()
        }
    }

    private func dismissChildPopups(parentID: UUID) {
        guard let parentIndex = popupControllers.firstIndex(where: { $0.id == parentID }) else { return }
        let childRange = popupControllers.index(after: parentIndex)..<popupControllers.endIndex
        guard !childRange.isEmpty else { return }

        for popup in popupControllers[childRange].reversed() {
            popup.controller.view.removeFromSuperview()
            popup.controller.removeFromParent()
        }
        popupControllers.removeSubrange(childRange)
    }

    func dismissAllPopups() {
        clearLookupHighlights()
        for popup in popupControllers.reversed() {
            popup.controller.view.removeFromSuperview()
            popup.controller.removeFromParent()
        }
        popupControllers.removeAll()
    }

    @available(iOS 18.0, *)
    func updateSelectionHighlight(text: String, charRects: [CGRect]) {
        guard let owner else { return }
        let matchedCount: Int?
        if let cachedSelectionMatch, cachedSelectionMatch.text == text {
            matchedCount = cachedSelectionMatch.matchedCount
        } else {
            matchedCount = LookupEngine.shared.lookup(text).first?.matched.count
            cachedSelectionMatch = (text: text, matchedCount: matchedCount)
        }

        guard let matchedCount else {
            clearSelectionHighlight()
            return
        }

        let rects = charRects.prefix(matchedCount).map { $0.insetBy(dx: -2, dy: -2) }
        guard !rects.isEmpty else {
            clearSelectionHighlight()
            return
        }

        let highlight = selectionHighlightView ?? {
            let view = UIView(frame: owner.view.bounds)
            view.isUserInteractionEnabled = false
            owner.view.addSubview(view)
            selectionHighlightView = view
            return view
        }()

        highlight.frame = owner.view.bounds
        highlight.layer.sublayers?.removeAll()

        let path = UIBezierPath()
        for rect in rects {
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: 2))
        }
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.fillColor = UIColor.systemYellow.withAlphaComponent(0.38).cgColor
        shapeLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.9).cgColor
        shapeLayer.lineWidth = 1.5
        highlight.layer.addSublayer(shapeLayer)
    }

    func clearSelectionHighlight() {
        selectionHighlightView?.removeFromSuperview()
        selectionHighlightView = nil
    }

    @available(iOS 18.0, *)
    private func addLookupHighlight(for entries: [DictEntryData], charRects: [CGRect]) {
        guard let owner,
              let matched = entries.first?.matched
        else { return }

        let rects = charRects.prefix(matched.count).map { $0.insetBy(dx: -2, dy: -2) }
        guard !rects.isEmpty else { return }

        let path = UIBezierPath()
        for rect in rects {
            path.append(UIBezierPath(roundedRect: rect, cornerRadius: 2))
        }

        let highlight = UIView(frame: owner.view.bounds)
        highlight.isUserInteractionEnabled = false

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.fillColor = UIColor.systemGray.withAlphaComponent(0.3).cgColor
        highlight.layer.addSublayer(shapeLayer)

        owner.view.addSubview(highlight)
        lookupHighlightViews.append(highlight)
    }

    private func clearLookupHighlights() {
        for highlight in lookupHighlightViews {
            highlight.removeFromSuperview()
        }
        lookupHighlightViews.removeAll()
    }
}

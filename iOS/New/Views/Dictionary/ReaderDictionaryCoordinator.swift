//
//  ReaderDictionaryCoordinator.swift
//  Aidoku (iOS)
//
//  Created by GameFuzzy on 7/11/26.
//

import CHoshiDicts
import SwiftUI

final class ReaderDictionaryCoordinator {
    private final class PopupHitTestView: UIView {
        var popupFrame: CGRect = .zero

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard popupFrame.contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }

    private struct PopupController {
        let id: UUID
        let controller: UIViewController
    }

    private let popupAnimationDuration: TimeInterval = 0.1
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

        let entries: [LookupResult] = LookupEngine.shared.lookup(text)
        guard !entries.isEmpty else { return false }

        if !appendPopup {
            dismissAllPopups()
            addLookupHighlight(for: entries, charRects: charRects)
        }

        let popupID = UUID()
        let userConfig = UserConfig()
        var dictionaryStyles: [String: String] = [:]
        for style in LookupEngine.shared.getStyles() {
            dictionaryStyles[String(style.dict_name)] = String(style.styles)
        }
        let availableFrame = owner.barsHidden
            ? owner.view.bounds
            : owner.view.safeAreaLayoutGuide.layoutFrame
        let isVertical = anchorRect.height > anchorRect.width * 1.15
        let layout = PopupLayout(
            selectionRect: anchorRect,
            availableFrame: availableFrame,
            maxWidth: CGFloat(userConfig.popupWidth),
            maxHeight: CGFloat(userConfig.popupHeight),
            isVertical: isVertical,
            isFullWidth: false
        )
        let popupFrame = CGRect(
            x: layout.position.x - layout.width / 2,
            y: layout.position.y - layout.height / 2,
            width: layout.width,
            height: layout.height
        )
        let popupView = PopupView(
            userConfig: userConfig,
            selectionData: .init(text: text, sentence: text, rect: anchorRect),
            lookupResults: entries,
            dictionaryStyles: dictionaryStyles,
            availableFrame: availableFrame,
            isVertical: isVertical,
            isFullWidth: false,
            clearSelection: false,
            onTextSelected: { [weak self] selection in
                guard let self else { return nil }
                _ = self.performLookup(
                    text: selection.text,
                    anchorRect: selection.rect,
                    appendPopup: true
                )
                return nil
            },
            onTapOutside: { [weak self] in
                self?.dismissChildPopups(parentID: popupID)
            },
            onSwipeDismiss: { [weak self] in
                self?.dismissTopPopup()
            },
            onPause: nil,
            wasPaused: false
        )

        let containerController = UIViewController()
        let containerView = PopupHitTestView()
        containerView.popupFrame = popupFrame
        containerView.backgroundColor = .clear
        containerController.view = containerView
        containerController.view.translatesAutoresizingMaskIntoConstraints = false

        let hostingController = UIHostingController(rootView: popupView)
        hostingController.view.backgroundColor = UIColor.clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.alpha = 0
        hostingController.view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)

        containerController.addChild(hostingController)
        containerController.view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: containerController.view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: containerController.view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: containerController.view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: containerController.view.bottomAnchor)
        ])
        hostingController.didMove(toParent: containerController)

        owner.add(child: containerController)
        NSLayoutConstraint.activate([
            containerController.view.topAnchor.constraint(equalTo: owner.view.topAnchor),
            containerController.view.leadingAnchor.constraint(equalTo: owner.view.leadingAnchor),
            containerController.view.trailingAnchor.constraint(equalTo: owner.view.trailingAnchor),
            containerController.view.bottomAnchor.constraint(equalTo: owner.view.bottomAnchor)
        ])

        popupControllers.append(PopupController(id: popupID, controller: containerController))
        UIView.animate(
            withDuration: popupAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut]
        ) {
            hostingController.view.alpha = 1
            hostingController.view.transform = .identity
        }
        return true
    }

    func dismissTopPopup() {
        guard let popup = popupControllers.popLast() else { return }
        hideAndRemove(popup)

        if popupControllers.isEmpty {
            clearLookupHighlights()
        }
    }

    private func dismissChildPopups(parentID: UUID) {
        guard let parentIndex = popupControllers.firstIndex(where: { $0.id == parentID }) else { return }
        let childRange = popupControllers.index(after: parentIndex)..<popupControllers.endIndex
        guard !childRange.isEmpty else { return }

        for popup in popupControllers[childRange].reversed() {
            hideAndRemove(popup)
        }
        popupControllers.removeSubrange(childRange)
    }

    func dismissAllPopups() {
        clearLookupHighlights()
        for popup in popupControllers.reversed() {
            hideAndRemove(popup)
        }
        popupControllers.removeAll()
    }

    private func hideAndRemove(_ popup: PopupController) {
        UIView.animate(
            withDuration: popupAnimationDuration,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            popup.controller.view.alpha = 0
            popup.controller.view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        } completion: { _ in
            popup.controller.view.removeFromSuperview()
            popup.controller.removeFromParent()
        }
    }

    @available(iOS 18.0, *)
    func updateSelectionHighlight(text: String, charRects: [CGRect]) {
        guard let owner else { return }

        let matchedCount: Int?
        if let cachedSelectionMatch, cachedSelectionMatch.text == text {
            matchedCount = cachedSelectionMatch.matchedCount
        } else {
            matchedCount = LookupEngine.shared.lookup(text).first.flatMap { String($0.matched).count }
            cachedSelectionMatch = (text: text, matchedCount: matchedCount)
        }

        guard
            let matchedCount,
            case let rects = charRects.prefix(matchedCount).map({ $0.insetBy(dx: -2, dy: -2) }),
            !rects.isEmpty
        else {
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
    private func addLookupHighlight(for entries: [LookupResult], charRects: [CGRect]) {
        guard
            let owner,
            let matched = entries.first.flatMap({ String($0.matched) })
        else {
            return
        }

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

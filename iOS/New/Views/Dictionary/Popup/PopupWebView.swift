//
//  PopupWebView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Based on: https://github.com/Manhhao/Hoshi-Reader/blob/ff31274acf44683e5b61abdfb2a273fc738d4711/Features/Popup/PopupWebView.swift
//  Modified for use in Aidoku
//

// swiftlint:disable comment_whitespace comment_spacing

import SwiftUI
import UIKit
import WebKit

struct SelectionData {
    let text: String
    let sentence: String
    let rect: CGRect
    var normalizedOffset: Int?
    var clozeOffset: Int?
}

//class AudioHandler: NSObject, WKURLSchemeHandler {
//    private var tasks = Set<ObjectIdentifier>()
//
//    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
//        guard let requestUrl = task.request.url,
//              let components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false),
//              let targetUrlString = components.queryItems?.first(where: { $0.name == "url" })?.value,
//              let targetUrl = URL(string: targetUrlString) else {
//            task.didFailWithError(URLError(.badURL))
//            return
//        }
//
//        let taskId = ObjectIdentifier(task)
//        tasks.insert(taskId)
//
//        Task {
//            do {
//                let request = URLRequest(url: targetUrl, timeoutInterval: 4)
//                let (data, _) = try await URLSession.shared.data(for: request)
//
//                await MainActor.run {
//                    guard self.tasks.contains(taskId) else { return }
//
//                    let response = HTTPURLResponse(
//                        url: requestUrl,
//                        statusCode: 200,
//                        httpVersion: "HTTP/1.1",
//                        headerFields: [
//                            "Access-Control-Allow-Origin": "*",
//                            "Content-Type": "application/json"
//                        ]
//                    )!
//                    task.didReceive(response)
//                    task.didReceive(data)
//                    task.didFinish()
//                }
//            } catch {
//                await MainActor.run {
//                    guard self.tasks.contains(taskId) else { return }
//                    task.didFailWithError(error)
//                }
//            }
//        }
//    }
//
//    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
//        tasks.remove(ObjectIdentifier(task))
//    }
//}

//class ImageHandler: NSObject, WKURLSchemeHandler {
//    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
//        guard let requestUrl = task.request.url,
//              let components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false),
//              let dictionary = components.queryItems?.first(where: { $0.name == "dictionary" })?.value,
//              let mediaPath = components.queryItems?.first(where: { $0.name == "path" })?.value else {
//            task.didFailWithError(URLError(.badURL))
//            return
//        }
//
//        LookupEngine.shared.withMediaFile(dictName: dictionary, mediaPath: mediaPath) { data in
//            let mime = mimeType(for: mediaPath)
//            Task { @MainActor in
//                guard !data.isEmpty else {
//                    task.didFailWithError(URLError(.fileDoesNotExist))
//                    return
//                }
//
//                let response = URLResponse(
//                    url: requestUrl,
//                    mimeType: mime,
//                    expectedContentLength: data.count,
//                    textEncodingName: nil
//                )
//                task.didReceive(response)
//                task.didReceive(data)
//                task.didFinish()
//            }
//        }
//    }
//
//    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
//
//    private func mimeType(for path: String) -> String {
//        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
//        case "png": return "image/png"
//        case "jpg", "jpeg": return "image/jpeg"
//        case "gif": return "image/gif"
//        case "webp": return "image/webp"
//        case "avif": return "image/avif"
//        case "heic": return "image/heic"
//        case "svg": return "image/svg+xml"
//        default: return "application/octet-stream"
//        }
//    }
//}

//class DocumentResourceHandler: NSObject, WKURLSchemeHandler {
//    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
//        guard let url = urlSchemeTask.request.url else { return }
//
//        let fileName = url.deletingPathExtension().lastPathComponent
//        do {
//            guard let fontFile = try FontManager.shared.fontUrl(name: fileName, verticalWriting: false) else {
//                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
//                return
//            }
//
//            let data = try Data(contentsOf: fontFile, options: .mappedIfSafe)
//            let response = URLResponse(
//                url: url,
//                mimeType: mimeType(for: fontFile),
//                expectedContentLength: data.count,
//                textEncodingName: nil
//            )
//
//            urlSchemeTask.didReceive(response)
//            urlSchemeTask.didReceive(data)
//            urlSchemeTask.didFinish()
//        } catch {
//            urlSchemeTask.didFailWithError(error)
//        }
//    }
//
//    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
//
//    private func mimeType(for url: URL) -> String {
//        switch url.pathExtension.lowercased() {
//        case "otf": return "font/otf"
//        case "woff": return "font/woff"
//        case "woff2": return "font/woff2"
//        default: return "font/ttf"
//        }
//    }
//}

struct PopupWebView: UIViewRepresentable {
    let content: String
    let position: CGPoint
    var scale: CGFloat = 1
    var clearSelection: Bool
    var dictionaryStyles: [String: String] = [:]
    var lookupEntries: [[String: Any]] = []
    var scanNonJapaneseText: Bool = true
    var scanLength: Int = 16
    var backTrigger: Bool = false
    var forwardTrigger: Bool = false
    var onMine: (([String: String], UUID) async -> Bool)?
    var onTextSelected: ((SelectionData) -> Int?)?
    var onTapOutside: (() -> Void)?
    var onSwipeDismiss: (() -> Void)?
    var onRedirect: ((String) -> [[String: Any]])?
    var scrollViewBounces: Bool = false
    var onScrollViewOffsetChanged: ((CGFloat) -> Void)?
    var onScrollViewWillBeginDragging: (() -> Void)?
    var onScrollViewDidEndDragging: (() -> Void)?
    var onScrollViewDidEndDecelerating: (() -> Void)?

//    private static let swipeDismissJs = """
//    (function() {
//        if (!window.swipeThreshold) {
//            return;
//        }
//        var startX, startY;
//        document.addEventListener('touchstart', function(e) {
//            startX = e.touches[0].clientX;
//            startY = e.touches[0].clientY;
//        });
//        document.addEventListener('touchend', function(e) {
//            var dx = e.changedTouches[0].clientX - startX;
//            var dy = e.changedTouches[0].clientY - startY;
//            var hasSelection = window.getSelection().toString();
//            
//            if (Math.abs(dx) > window.swipeThreshold && Math.abs(dy) < 20 && !hasSelection) {
//                webkit.messageHandlers.swipeDismiss.postMessage(null);
//            }
//        });
//    })();
//    """

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "openLink")
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "tapOutside")
//        config.userContentController.add(context.coordinator, name: "swipeDismiss")
//        config.userContentController.add(context.coordinator, name: "playWordAudio")
        config.userContentController.add(context.coordinator, name: "buttonRects")
        config.userContentController.add(context.coordinator, name: "showNotes")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "mineEntry")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "duplicateCheck")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "getEntries")
        config.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "lookupRedirect")
//        config.setURLSchemeHandler(AudioHandler(), forURLScheme: "audio")
//        config.setURLSchemeHandler(ImageHandler(), forURLScheme: "image")
//        config.setURLSchemeHandler(DocumentResourceHandler(), forURLScheme: "local-resources")
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = scrollViewBounces
        webView.scrollView.keyboardDismissMode = .onDrag
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.delegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if !context.coordinator.wasLoaded {
            context.coordinator.currentContent = content
            context.coordinator.wasLoaded = true
            let html = constructHtml(content: content)
            webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        }

        if context.coordinator.clearSelection != clearSelection {
            context.coordinator.clearSelection = clearSelection
            webView.evaluateJavaScript("window.hoshiSelection.clearSelection()")
        }

        if context.coordinator.lastBackTrigger != backTrigger {
            context.coordinator.lastBackTrigger = backTrigger
            webView.evaluateJavaScript("window.navigateBack()")
        }

        if context.coordinator.lastForwardTrigger != forwardTrigger {
            context.coordinator.lastForwardTrigger = forwardTrigger
            webView.evaluateJavaScript("window.navigateForward()")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
//        coordinator.removeWordAddedObserver()
//        Task {
//            await WordAudioPlayer.shared.stop(id: coordinator.id)
//        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapOutside")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "swipeDismiss")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playWordAudio")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "buttonRects")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "showNotes")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mineEntry", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "duplicateCheck", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "getEntries", contentWorld: .page)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "lookupRedirect", contentWorld: .page)
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate, UIScrollViewDelegate {
        var parent: PopupWebView
        var currentContent: String = ""
        var wasLoaded: Bool = false
        var clearSelection: Bool = false
        var lastBackTrigger: Bool = false
        var lastForwardTrigger: Bool = false
        var entries: [[String: Any]] = []
        weak var webView: WKWebView?
        private var buttons: [String: UIButton] = [:]
        // swiftlint:disable:next large_tuple
        private var buttonActions: [UIButton: (kind: String, entryIndex: Int, slotIndex: Int)] = [:]
//        private var wordAddedObserver: NSObjectProtocol?
        let id = UUID()

        init(parent: PopupWebView) {
            self.parent = parent
            super.init()
//            wordAddedObserver = NotificationCenter.default.addObserver(
//                forName: AnkiManager.wordAddedNotification,
//                object: nil,
//                queue: .main
//            ) { [weak self] _ in
//                MainActor.assumeIsolated {
//                    self?.webView?.evaluateJavaScript("recheckDuplicates()")
//                }
//            }
        }

//        func removeWordAddedObserver() {
//            if let wordAddedObserver {
//                NotificationCenter.default.removeObserver(wordAddedObserver)
//                self.wordAddedObserver = nil
//            }
//        }

        private func updateButtons(_ rects: [[String: Any]], in webView: WKWebView) {
            var activeKeys = Set<String>()
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 13 * parent.scale, weight: .medium)

            for rect in rects {
                guard let kind = rect["kind"] as? String,
                      let entryIndex = rect["entryIndex"] as? Int,
                      let x = rect["x"] as? CGFloat,
                      let y = rect["y"] as? CGFloat,
                      let width = rect["width"] as? CGFloat,
                      let height = rect["height"] as? CGFloat,
                      width > 0, height > 0 else {
                    continue
                }

                let slotIndex = rect["slotIndex"] as? Int ?? 0
//                if kind != "audio", !AnkiManager.shared.cardFormats.indices.contains(slotIndex) {
//                    continue
//                }
                let key = "\(kind)-\(entryIndex)-\(slotIndex)"
                activeKeys.insert(key)

                let button: UIButton
                if let existing = buttons[key] {
                    button = existing
                } else {
                    button = UIButton(type: .system)
                    button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
                    button.tintColor = .secondaryLabel
                    buttons[key] = button
                    webView.scrollView.addSubview(button)
                }

                buttonActions[button] = (kind, entryIndex, slotIndex)
                button.frame = CGRect(x: x, y: y, width: width, height: height)
                let state = rect["state"] as? String ?? "default"
                button.setImage(symbolImage(kind: kind, state: state, slotIndex: slotIndex, config: symbolConfig), for: .normal)
                button.isEnabled = rect["enabled"] as? Bool ?? true
                button.alpha = button.isEnabled ? (kind == "note" ? 0.58 : 0.85) : 0.55
            }

            for key in buttons.keys.filter({ !activeKeys.contains($0) }) {
                if let button = buttons.removeValue(forKey: key) {
                    buttonActions.removeValue(forKey: button)
                    button.removeFromSuperview()
                }
            }
        }

        private func symbolImage(kind: String, state: String, slotIndex: Int, config: UIImage.SymbolConfiguration) -> UIImage? {
            if kind == "audio" {
                return UIImage(systemName: state == "error" ? "speaker.slash" : "speaker.wave.2", withConfiguration: config)
            }
            if kind == "note" {
                let noteConfig = UIImage.SymbolConfiguration(pointSize: 9 * parent.scale, weight: .medium)
                return UIImage(systemName: "magnifyingglass", withConfiguration: noteConfig)
            }
//            guard AnkiManager.shared.cardFormats.indices.contains(slotIndex) else { return nil }
//            var icon = AnkiManager.shared.cardFormats[slotIndex].icon
//            let isSmall = icon.hasSuffix(".small")
//            if isSmall {
//                icon = String(icon.dropLast(".small".count))
//            }
//            let name = state == "duplicate" ? (AnkiCardFormat.duplicateIcons[icon] ?? icon) : icon
//            let iconConfig = isSmall ? UIImage.SymbolConfiguration(pointSize: 10 * parent.scale, weight: .medium) : config
//            return UIImage(systemName: name, withConfiguration: iconConfig)
            return nil
        }

        @objc private func buttonTapped(_ sender: UIButton) {
            guard let action = buttonActions[sender] else { return }
            switch action.kind {
            case "audio":
                webView?.evaluateJavaScript("playEntryAudio(\(action.entryIndex))")
            case "note":
                webView?.evaluateJavaScript("showNotesAtIndex(\(action.entryIndex), \(action.slotIndex))")
            default:
                webView?.evaluateJavaScript("mineEntryAtIndex(\(action.entryIndex), \(action.slotIndex))")
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScrollViewOffsetChanged?(scrollView.contentOffset.y)
            guard scrollView.contentOffset.x != 0 else { return }
            scrollView.contentOffset.x = 0
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onScrollViewWillBeginDragging?()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            parent.onScrollViewDidEndDragging?()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            parent.onScrollViewDidEndDecelerating?()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            entries = parent.lookupEntries
            webView.callAsyncJavaScript(
                """
                window.dictionaryStyles = dictionaryStyles;
                window.entryCount = entryCount;
                window.renderPopup();
                """,
                arguments: [
                    "dictionaryStyles": parent.dictionaryStyles,
                    "entryCount": entries.count
                ],
                in: nil,
                in: .page,
                completionHandler: nil
            )
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
//            if message.name == "mineEntry", let content = message.body as? [String: String] {
//                guard let slotIndex = content["slotIndex"].flatMap(Int.init),
//                      AnkiManager.shared.cardFormats.indices.contains(slotIndex) else {
//                    return (false, nil)
//                }
//                return (await parent.onMine?(content, AnkiManager.shared.cardFormats[slotIndex].id) ?? false, nil)
//            }
//            if message.name == "duplicateCheck", let fields = message.body as? [String: String] {
//                return (await AnkiManager.shared.checkDuplicates(fields: fields), nil)
//            }
            if message.name == "getEntries", let body = message.body as? [String: Any] {
                let start = body["start"] as? Int ?? 0
                let count = body["count"] as? Int ?? 0
                return (Array(entries[start..<start + count]), nil)
            }
            if message.name == "lookupRedirect", let query = message.body as? String {
                entries = parent.onRedirect?(query) ?? []
                return (entries.count, nil)
            }
            return (nil, nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "openLink", let urlString = message.body as? String,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            } else if message.name == "tapOutside" {
                parent.onTapOutside?()
                message.webView?.evaluateJavaScript("window.hoshiSelection.clearSelection()")
            } else if message.name == "swipeDismiss" {
                parent.onSwipeDismiss?()
            } else if message.name == "buttonRects",
                    let rects = message.body as? [[String: Any]] {
                guard let webView = message.webView else { return }
                updateButtons(rects, in: webView)
//            } else if message.name == "showNotes", let fields = message.body as? [String: String],
//                    let slotIndex = fields["slotIndex"].flatMap(Int.init) {
//                Task { await AnkiManager.shared.showNotes(fields: fields, formatIndex: slotIndex) }
            } else if message.name == "textSelected" {
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String,
                      let sentence = body["sentence"] as? String,
                      let rectData = body["rect"] as? [String: Any],
                      let x = rectData["x"] as? CGFloat,
                      let y = rectData["y"] as? CGFloat,
                      let w = rectData["width"] as? CGFloat,
                      let h = rectData["height"] as? CGFloat else {
                    return
                }
                let adjustedInset = message.webView?.scrollView.adjustedContentInset ?? .zero
                let rect = CGRect(
                    x: parent.position.x + x + adjustedInset.left,
                    y: parent.position.y + y + adjustedInset.top,
                    width: w,
                    height: h
                )
                let clozeOffset = body["clozeOffset"] as? Int
                let selectionData = SelectionData(text: text, sentence: sentence, rect: rect, clozeOffset: clozeOffset)

                if let highlightCount = parent.onTextSelected?(selectionData) {
                    message.webView?.evaluateJavaScript("window.hoshiSelection.highlightSelection(\(highlightCount))")
                }
//            } else if message.name == "playWordAudio",
//                    let content = message.body as? [String: Any],
//                    let urlString = content["url"] as? String {
//                let requestedMode = (content["mode"] as? String).flatMap(AudioPlaybackMode.init) ?? .interrupt
//                Task(priority: .userInitiated) {
//                    await WordAudioPlayer.shared.play(urlString: urlString, requestedMode: requestedMode, id: self.id)
//                }
            }
        }
    }

    private func constructHtml(content: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <link rel="stylesheet" href="popup.css">
            <style>
                html, body { --popup-scale: \(scale); }
            </style>
            <script>
                window.scanNonJapaneseText = \(scanNonJapaneseText);
                window.scanLength = \(scanLength);
            </script>
            <script src="selection.js"></script>
            <script src="popup.js"></script>
        </head>
        <body>
            \(content)
            <div class="overlay">
                <div class="overlay-close" onclick="closeOverlay()">×</div>
                <div class="overlay-content"></div>
            </div>
        </body>
        </html>
        """
    }
}

// swiftlint:enable comment_whitespace comment_spacing

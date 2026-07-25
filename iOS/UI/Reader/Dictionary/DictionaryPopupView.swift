//
//  DictionaryPopupView.swift
//  Aidoku (iOS)
//
//  Created with reference to Hoshi Reader by Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import SwiftUI
import WebKit

private enum DictionaryAudioPlaybackMode: String {
    case interrupt
    case duck
    case mix
}

@MainActor
private final class DictionaryWordAudioPlayer {
    static let shared = DictionaryWordAudioPlayer()

    private var player: AVPlayer?
    private var playToEndObserver: NSObjectProtocol?
    private var failedToPlayObserver: NSObjectProtocol?
    private var playbackID: UUID?

    private init() {}

    func stop(id: UUID? = nil) {
        if let id, id != playbackID {
            return
        }
        stopPlayback(deactivateSession: true)
    }

    func play(urlString: String, mode: DictionaryAudioPlaybackMode, id: UUID) {
        guard let url = URL(string: urlString) else { return }

        stopPlayback(deactivateSession: false)

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: categoryOptions(for: mode))
            try session.setActive(true, options: [])
        } catch {
            return
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playbackID = id

        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.stop()
            }
        }

        failedToPlayObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.stop()
            }
        }

        player.play()
    }

    private func stopPlayback(deactivateSession: Bool) {
        player?.pause()
        player = nil
        playbackID = nil

        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
            self.playToEndObserver = nil
        }
        if let failedToPlayObserver {
            NotificationCenter.default.removeObserver(failedToPlayObserver)
            self.failedToPlayObserver = nil
        }

        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    private func categoryOptions(for mode: DictionaryAudioPlaybackMode) -> AVAudioSession.CategoryOptions {
        switch mode {
            case .interrupt:
                []
            case .duck:
                [.mixWithOthers, .duckOthers]
            case .mix:
                [.mixWithOthers]
        }
    }
}

private final class DictionaryAudioURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private var activeTasks = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let requestURL = task.request.url,
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let targetURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let targetURL = URL(string: targetURLString)
        else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        let taskID = ObjectIdentifier(task)
        activeTasks.insert(taskID)

        Task { [weak self] in
            guard let self else { return }

            do {
                let request = URLRequest(url: targetURL, timeoutInterval: 2.0)
                let (data, response) = try await URLSession.shared.data(for: request)

                await MainActor.run {
                    guard self.activeTasks.contains(taskID) else { return }
                    let contentType = (response as? HTTPURLResponse)?
                        .value(forHTTPHeaderField: "Content-Type") ?? "application/json"
                    let proxyResponse = HTTPURLResponse(
                        url: requestURL,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: [
                            "Access-Control-Allow-Origin": "*",
                            "Content-Type": contentType
                        ]
                    )!
                    task.didReceive(proxyResponse)
                    task.didReceive(data)
                    task.didFinish()
                }
            } catch {
                await MainActor.run {
                    guard self.activeTasks.contains(taskID) else { return }
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(task))
    }
}

@available(iOS 18.0, *)
struct DictionaryPopupSelection {
    let text: String
    let rect: CGRect?
}

@available(iOS 18.0, *)
struct DictionaryPopupView: View {
    let entries: [DictEntryData]
    let dictionaryStyles: [String: String]
    let anchorRect: CGRect
    let screenSize: CGSize
    let onLookup: (DictionaryPopupSelection) -> Void
    let onDismiss: () -> Void
    let onTapOutside: () -> Void

    private var maxWidth: CGFloat {
        let storedValue = UserDefaults.standard.double(forKey: "Reader.dictionaryPopupWidth")
        let width = storedValue > 0 ? storedValue : 320
        return min(max(CGFloat(width), 220), 500)
    }

    private var maxHeight: CGFloat {
        let storedValue = UserDefaults.standard.double(forKey: "Reader.dictionaryPopupHeight")
        let height = storedValue > 0 ? storedValue : 250
        return min(max(CGFloat(height), 160), 350)
    }

    private let padding: CGFloat = 8
    private let borderPadding: CGFloat = 6

    private var isVerticalSelection: Bool {
        anchorRect.height > anchorRect.width * 1.15
    }

    private var spaceLeft: CGFloat {
        anchorRect.minX - padding
    }

    private var spaceRight: CGFloat {
        screenSize.width - anchorRect.maxX - padding
    }

    private var spaceAbove: CGFloat {
        anchorRect.minY - padding
    }

    private var spaceBelow: CGFloat {
        screenSize.height - anchorRect.maxY - padding
    }

    private var popupWidth: CGFloat {
        if isVerticalSelection {
            let available = max(spaceLeft, spaceRight) - borderPadding
            return max(1, min(available, maxWidth))
        }
        return min(screenSize.width - borderPadding * 2, maxWidth)
    }

    private var popupHeight: CGFloat {
        if isVerticalSelection {
            return maxHeight
        }
        let availableHeight = max(spaceBelow, spaceAbove)
        return max(1, min(availableHeight - borderPadding, maxHeight))
    }

    private var popupOrigin: CGPoint {
        let showOnRight = spaceRight >= spaceLeft
        let showBelow = spaceBelow >= popupHeight || spaceBelow >= spaceAbove

        if isVerticalSelection {
            var x: CGFloat
            if showOnRight {
                x = anchorRect.maxX + padding
            } else {
                x = anchorRect.minX - padding - popupWidth
            }
            x = max(borderPadding, min(x, screenSize.width - popupWidth - borderPadding))

            var y = anchorRect.minY
            y = max(borderPadding, min(y, screenSize.height - popupHeight - borderPadding))
            return CGPoint(x: x, y: y)
        } else {
            var x = anchorRect.minX + (popupWidth / 2)
            x = max(popupWidth / 2 + borderPadding, min(x, screenSize.width - popupWidth / 2 - borderPadding))

            var y: CGFloat
            if showBelow {
                y = anchorRect.maxY + padding + (popupHeight / 2)
            } else {
                y = anchorRect.minY - padding - (popupHeight / 2)
            }
            y = max(popupHeight / 2, min(y, screenSize.height - popupHeight / 2))
            return CGPoint(x: x - popupWidth / 2, y: y - popupHeight / 2)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // tap outside to dismiss
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            DictionaryPopupWebView(
                entries: entries,
                dictionaryStyles: dictionaryStyles,
                popupOrigin: popupOrigin,
                onLookup: onLookup,
                onTapOutside: onTapOutside
            )
                .frame(width: max(1, popupWidth), height: max(1, popupHeight))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(.separator).opacity(0.5), lineWidth: 1)
                )
                .offset(x: popupOrigin.x, y: popupOrigin.y)
        }
        .ignoresSafeArea()
    }
}

@available(iOS 18.0, *)
struct DictionaryPopupWebView: UIViewRepresentable {
    let entries: [DictEntryData]
    let dictionaryStyles: [String: String]
    let popupOrigin: CGPoint
    let onLookup: (DictionaryPopupSelection) -> Void
    let onTapOutside: () -> Void

    private static let popupJs: String = {
        guard let url = Bundle.main.url(forResource: "popup", withExtension: "js", subdirectory: nil),
              let js = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return js
    }()

    private static let selectionJs: String = {
        guard let url = Bundle.main.url(forResource: "selection", withExtension: "js", subdirectory: nil),
              let js = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return js
    }()

    private static let popupCss: String = {
        guard let url = Bundle.main.url(forResource: "popup", withExtension: "css", subdirectory: nil),
              let css = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return css
    }()

    private var audioSources: [String] {
        ((UserDefaults.standard.array(forKey: "Reader.dictionaryAudioSources") as? [String]) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var audioAutoplayEnabled: Bool {
        UserDefaults.standard.bool(forKey: "Reader.dictionaryAudioAutoplay")
    }

    private var audioPlaybackMode: DictionaryAudioPlaybackMode {
        let rawValue = UserDefaults.standard.string(forKey: "Reader.dictionaryAudioPlaybackMode")
        return rawValue.flatMap(DictionaryAudioPlaybackMode.init(rawValue:)) ?? .interrupt
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            popupOrigin: popupOrigin,
            onLookup: onLookup,
            onTapOutside: onTapOutside
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "openLink")
        config.userContentController.add(context.coordinator, name: "tapOutside")
        config.userContentController.add(context.coordinator, name: "textSelected")
        config.userContentController.add(context.coordinator, name: "playWordAudio")
        config.setURLSchemeHandler(DictionaryAudioURLSchemeHandler(), forURLScheme: "audio")
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !context.coordinator.wasLoaded else { return }
        context.coordinator.wasLoaded = true

        let html = constructHtml()
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        Task { @MainActor in
            DictionaryWordAudioPlayer.shared.stop(id: coordinator.audioPlaybackID)
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "openLink")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tapOutside")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playWordAudio")
    }

    class Coordinator: NSObject, WKScriptMessageHandler {
        var wasLoaded = false
        let popupOrigin: CGPoint
        let onLookup: (DictionaryPopupSelection) -> Void
        let onTapOutside: () -> Void
        let audioPlaybackID = UUID()

        init(
            popupOrigin: CGPoint,
            onLookup: @escaping (DictionaryPopupSelection) -> Void,
            onTapOutside: @escaping () -> Void
        ) {
            self.popupOrigin = popupOrigin
            self.onLookup = onLookup
            self.onTapOutside = onTapOutside
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "openLink",
               let urlString = message.body as? String,
               let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            } else if message.name == "tapOutside" {
                onTapOutside()
                message.webView?.evaluateJavaScript("window.hoshiSelection.clearHighlight()")
            } else if message.name == "textSelected",
                      let selectedText = message.body as? String {
                onLookup(.init(text: selectedText, rect: nil))
            } else if message.name == "textSelected",
                      let body = message.body as? [String: Any],
                      let selectedText = body["text"] as? String {
                let selectionRect: CGRect?
                if let rectData = body["rect"] as? [String: Any],
                   let x = rectData["x"] as? Double,
                   let y = rectData["y"] as? Double,
                   let width = rectData["width"] as? Double,
                   let height = rectData["height"] as? Double {
                    let adjustedInset = message.webView?.scrollView.adjustedContentInset ?? .zero
                    selectionRect = CGRect(
                        x: popupOrigin.x + x + adjustedInset.left,
                        y: popupOrigin.y + y + adjustedInset.top,
                        width: width,
                        height: height
                    )
                } else {
                    selectionRect = nil
                }
                onLookup(.init(text: selectedText, rect: selectionRect))
            } else if message.name == "playWordAudio",
                      let body = message.body as? [String: Any],
                      let urlString = body["url"] as? String {
                let mode = (body["mode"] as? String)
                    .flatMap(DictionaryAudioPlaybackMode.init(rawValue:)) ?? .interrupt
                Task(priority: .userInitiated) { @MainActor in
                    DictionaryWordAudioPlayer.shared.play(
                        urlString: urlString,
                        mode: mode,
                        id: audioPlaybackID
                    )
                }
            }
        }
    }

    private func constructHtml() -> String {
        let stylesJson = (try? JSONEncoder().encode(dictionaryStyles))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let entriesJson = (try? JSONEncoder().encode(entries))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let audioSourcesJson = (try? JSONEncoder().encode(audioSources))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>\(Self.popupCss)</style>
            <script>
                // stub out handlers not needed for image reader popup
                window.webkit = window.webkit || {};
                window.webkit.messageHandlers = window.webkit.messageHandlers || {};
                if (!window.webkit.messageHandlers.mineEntry) {
                    window.webkit.messageHandlers.mineEntry = { postMessage: function() {} };
                }
                if (!window.webkit.messageHandlers.playWordAudio) {
                    window.webkit.messageHandlers.playWordAudio = { postMessage: function() {} };
                }
                if (!window.webkit.messageHandlers.duplicateCheck) {
                    window.webkit.messageHandlers.duplicateCheck = { postMessage: async function() { return false; } };
                }
                if (!window.webkit.messageHandlers.getEntry) {
                    window.webkit.messageHandlers.getEntry = { postMessage: async function(index) { return (window.lookupEntries || [])[index] || null; } };
                }
            </script>
            <script>\(Self.selectionJs)</script>
            <script>\(Self.popupJs)</script>
        </head>
        <body>
            <script>
                window.dictionaryStyles = \(stylesJson);
                window.lookupEntries = \(entriesJson);
                window.entryCount = window.lookupEntries.length;
                window.collapseDictionaries = false;
                window.compactGlossaries = false;
                window.audioSources = \(audioSourcesJson);
                window.audioEnableAutoplay = \(audioAutoplayEnabled);
                window.audioPlaybackMode = "\(audioPlaybackMode.rawValue)";
                window.needsAudio = false;
                window.customCSS = "";
            </script>
            <div id="entries-container"></div>
            <div class="overlay">
                <div class="overlay-close" onclick="closeOverlay()">×</div>
                <div class="overlay-content"></div>
            </div>
            <script>
                window.renderPopup();
            </script>
        </body>
        </html>
        """
    }
}

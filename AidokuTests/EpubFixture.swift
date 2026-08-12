//
//  EpubFixture.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/11/26.
//

@testable import Aidoku
import Foundation
import Testing
import UIKit
import WebKit
import ZIPFoundation

/// What the ePub tests need in common: archives synthesised in memory, a web view installed in the
/// host application's window, and the polling that stands in for a navigation delegate.
///
/// Archives are built here rather than read from disk so that the suite stays hermetic and no book
/// enters the repository.
enum EpubFixture {
    static let viewportSize = CGSize(width: 320, height: 480)

    static func makeArchive(entries: [String: Data]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                provider: { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                }
            )
        }
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Rendered at scale 1 so the pixel dimensions are the ones written here rather than the
    /// device's, which a test asserting on `naturalWidth` depends on.
    static func png(size: CGSize = CGSize(width: 4, height: 4)) -> Data {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func page(body: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>page</title></head><body>\(body)</body></html>
        """
    }

    /// Enough prose to occupy several columns at the fixture's viewport size.
    static func prose(paragraphs: Int) -> String {
        (1...paragraphs)
            .map { "<p>Paragraph \($0). \(String(repeating: "word ", count: 40))</p>" }
            .joined()
    }

    @MainActor
    static func makeWebView(configuration: WKWebViewConfiguration) throws -> WKWebView {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: viewportSize), configuration: configuration)
        try install(webView, size: viewportSize)
        return webView
    }

    /// The host application's window gives the web view a real viewport, without which the
    /// injected meta element has nothing to resolve device-width against.
    @MainActor
    static func install(_ webView: WKWebView, size: CGSize) throws {
        webView.frame = CGRect(origin: .zero, size: size)
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        try #require(window).addSubview(webView)
        webView.layoutIfNeeded()
    }

    @MainActor
    static func dismantle(_ webView: WKWebView) {
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    @MainActor
    static func load(
        spinePath: String,
        from archiveURL: URL,
        insetBehaviour: UIScrollView.ContentInsetAdjustmentBehavior = .automatic
    ) async throws -> WKWebView {
        let provider = try EpubZipResourceProvider(url: archiveURL)
        let configuration = try await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = try makeWebView(configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = insetBehaviour

        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: spinePath))))
        try await waitForDocument(in: webView)
        try await waitForImages(in: webView)

        return webView
    }

    /// A renderer whose web view is installed at a known size. A page count belongs to a viewport,
    /// so a renderer measured outside a window would be measuring nothing.
    @MainActor
    static func makeRenderer(for archiveURL: URL, size: CGSize = viewportSize) async throws -> EpubSpineRenderer {
        let provider = try EpubZipResourceProvider(url: archiveURL)
        let renderer = try await EpubSpineRenderer(provider: provider)
        try install(renderer.webView, size: size)
        return renderer
    }

    /// Polls rather than waiting on the navigation delegate, which keeps the fixture free of a
    /// delegate object whose only purpose is to resume a continuation.
    ///
    /// The web view's URL is checked as well as the document's state: the empty document a web
    /// view starts with already reports itself as complete.
    @MainActor
    static func waitForDocument(in webView: WKWebView, timeout: TimeInterval = 10) async throws {
        try await waitUntil(timeout: timeout) {
            guard webView.url?.scheme == EpubSchemeHandler.scheme, !webView.isLoading else { return false }
            let state = try? await evaluate("document.readyState", in: webView) as? String
            return state == "complete"
        }
    }

    /// A blocked image reports `complete` as well, so this settles both outcomes.
    @MainActor
    static func waitForImages(in webView: WKWebView, timeout: TimeInterval = 10) async throws {
        try await waitUntil(timeout: timeout) {
            let script = "String(Array.prototype.every.call(document.images, function(i) { return i.complete; }))"
            let done = try? await evaluate(script, in: webView) as? String
            return done == "true"
        }
    }

    static func waitUntil(timeout: TimeInterval, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("timed out after \(Int(timeout))s")
    }

    @MainActor
    static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script, contentWorld: EpubWebViewFactory.contentWorld)
    }

    /// Where the document is scrolled to, taken from the scroll view rather than from
    /// `window.pageXOffset`.
    ///
    /// The document's copy of the offset is updated by a rendering update, so it lags behind what
    /// is on screen whenever the web process has nothing else to draw. The scroll view holds the
    /// number the reader is looking at.
    @MainActor
    static func pageOffset(in webView: WKWebView) -> Double {
        Double(webView.scrollView.contentOffset.x)
    }

    /// A number read out of the document, which is how the layout is inspected without trusting
    /// the renderer's own measurement.
    @MainActor
    static func number(_ expression: String, in webView: WKWebView) async throws -> Double {
        let value = try await evaluate("String(\(expression))", in: webView) as? String
        let text = try #require(value)
        return try #require(Double(text))
    }

    /// Values are returned as one string and parsed here: passing structured values across the
    /// JavaScript boundary is less predictable than parsing a known format.
    static let probeScript = """
    (function() {
        function width(id) {
            var element = document.getElementById(id);
            return element ? element.naturalWidth : -1;
        }
        // Only stylesheets fetched from a URL are counted. The readium-css sheets are injected
        // inline and carry no href, so what remains is what the document itself asked the network
        // or the handler for, which is what this probes.
        var hrefs = [];
        for (var i = 0; i < document.styleSheets.length; i++) {
            var href = document.styleSheets[i].href;
            if (href) { hrefs.push(href); }
        }
        return [
            'internal=' + width('internal'),
            'remote=' + width('remote'),
            'local=' + width('local'),
            'sheets=' + hrefs.length,
            'sheetHrefs=' + hrefs.join(' '),
            'innerWidth=' + window.innerWidth
        ].join('\\n');
    })();
    """

    static func parse(_ report: String) -> [String: String] {
        report.split(separator: "\n").reduce(into: [:]) { result, line in
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return }
            result[String(parts[0])] = String(parts[1])
        }
    }
}

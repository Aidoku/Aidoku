//
//  EpubResourceLayerTests.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

@testable import Aidoku
import Foundation
import Testing
import UIKit
import WebKit
import ZIPFoundation

/// Serialised because the stub transport below is shared state.
@Suite(.serialized)
struct EpubResourceLayerTests {
    // MARK: - Zip provider

    @Test func zipProviderReadsEntries() async throws {
        let url = try Fixture.makeArchive(entries: ["OEBPS/page.xhtml": Data("hello".utf8)])
        defer { Fixture.remove(url) }

        let provider = try EpubZipResourceProvider(url: url)
        let data = try await provider.data(at: "OEBPS/page.xhtml")

        #expect(String(data: data, encoding: .utf8) == "hello")
    }

    @Test func zipProviderToleratesPathVariations() async throws {
        let url = try Fixture.makeArchive(entries: [
            "./OEBPS/Chapter One.xhtml": Data("dotted".utf8),
            "OEBPS/Images/Cover.png": Data("cover".utf8)
        ])
        defer { Fixture.remove(url) }

        let provider = try EpubZipResourceProvider(url: url)

        // A relative href resolves without the "./" prefix the archive was written with.
        let dotted = try await provider.data(at: "OEBPS/Chapter One.xhtml")
        #expect(String(data: dotted, encoding: .utf8) == "dotted")

        // Case differences are common between the manifest and the archive.
        let lowercased = try await provider.data(at: "oebps/images/cover.png")
        #expect(String(data: lowercased, encoding: .utf8) == "cover")
    }

    @Test func zipProviderThrowsForMissingEntry() async throws {
        let url = try Fixture.makeArchive(entries: ["OEBPS/page.xhtml": Data("hello".utf8)])
        defer { Fixture.remove(url) }

        let provider = try EpubZipResourceProvider(url: url)

        await #expect(throws: EpubResourceError.self) {
            try await provider.data(at: "OEBPS/missing.xhtml")
        }
    }

    @Test func zipProviderThrowsForUnopenableArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try Data("not a zip".utf8).write(to: url)
        defer { Fixture.remove(url) }

        #expect(throws: EpubResourceError.self) {
            _ = try EpubZipResourceProvider(url: url)
        }
    }

    // MARK: - Scheme handler

    @Test func schemeHandlerBuildsResourceURLs() {
        let url = EpubSchemeHandler.url(forResourcePath: "OEBPS/page.xhtml")
        #expect(url?.scheme == EpubSchemeHandler.scheme)
        #expect(url?.host == EpubSchemeHandler.host)
        #expect(url?.path == "/OEBPS/page.xhtml")
    }

    @Test func schemeHandlerReportsMimeTypes() {
        #expect(EpubSchemeHandler.mimeType(forPath: "OEBPS/page.xhtml") == "application/xhtml+xml")
        #expect(EpubSchemeHandler.mimeType(forPath: "OEBPS/style.CSS") == "text/css")
        #expect(EpubSchemeHandler.mimeType(forPath: "OEBPS/cover.jpeg") == "image/jpeg")
        #expect(EpubSchemeHandler.mimeType(forPath: "OEBPS/font.woff2") == "font/woff2")
        #expect(EpubSchemeHandler.mimeType(forPath: "OEBPS/unknown.bin") == "application/octet-stream")
    }

    /// Some toolchains name their spine documents `.xml` while the manifest declares them as
    /// XHTML. Serving those as generic XML costs the viewport, and nothing reports an error.
    @Test func schemeHandlerServesXMLNamedSpineDocumentsAsXHTML() {
        let xhtml = Data(Fixture.page(body: "<p>text</p>").utf8)
        #expect(EpubSchemeHandler.mimeType(forPath: "OPS/main0.xml", contents: xhtml) == "application/xhtml+xml")

        let other = Data("<?xml version=\"1.0\"?><metadata/>".utf8)
        #expect(EpubSchemeHandler.mimeType(forPath: "OPS/feedbooks.xml", contents: other) == "application/xml")

        // The package document and the navigation document stay XML whatever they contain.
        #expect(EpubSchemeHandler.mimeType(forPath: "OPS/fb.opf", contents: xhtml) == "application/xml")
        #expect(EpubSchemeHandler.mimeType(forPath: "OPS/fb.ncx", contents: xhtml) == "application/xml")
    }

    // MARK: - Remote provider

    @Test func remoteProviderFetchesThroughTheSuppliedMapping() async throws {
        StubURLProtocol.respond { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            return (200, Data(request.url?.path.utf8 ?? "".utf8))
        }
        defer { StubURLProtocol.reset() }

        let provider = EpubRemoteResourceProvider(
            baseURL: URL(string: "https://example.test/book/1")!,
            headers: ["Authorization": "Bearer token"],
            session: StubURLProtocol.session()
        )
        let data = try await provider.data(at: "OEBPS/page.xhtml")

        #expect(String(data: data, encoding: .utf8) == "/book/1/OEBPS/page.xhtml")
    }

    @Test func remoteProviderThrowsOnRefusedRequest() async throws {
        StubURLProtocol.respond { _ in (404, Data()) }
        defer { StubURLProtocol.reset() }

        let provider = EpubRemoteResourceProvider(
            baseURL: URL(string: "https://example.test/book/1")!,
            session: StubURLProtocol.session()
        )

        await #expect(throws: EpubResourceError.self) {
            try await provider.data(at: "OEBPS/page.xhtml")
        }
    }

    @Test func remoteProviderThrowsWhenThePathCannotBeAddressed() async throws {
        let provider = EpubRemoteResourceProvider(session: StubURLProtocol.session()) { _ in nil }

        await #expect(throws: EpubResourceError.self) {
            try await provider.data(at: "OEBPS/page.xhtml")
        }
    }

    // MARK: - Web view posture

    /// The security posture this slice exists to establish. A blocked image never decodes, so its
    /// `naturalWidth` stays at zero, and a blocked stylesheet never enters `document.styleSheets`.
    @MainActor
    @Test func hardenedWebViewBlocksRemoteAndFileResources() async throws {
        let localImageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        try Fixture.png().write(to: localImageURL)
        defer { Fixture.remove(localImageURL) }

        let page = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
        <link rel="stylesheet" type="text/css" href="style.css"/>
        <link rel="stylesheet" type="text/css" href="https://example.com/remote.css"/>
        </head>
        <body>
        <img id="internal" src="cover.png"/>
        <img id="remote" src="https://example.com/tracking-pixel.png"/>
        <img id="local" src="file://\(localImageURL.path)"/>
        </body>
        </html>
        """
        let archiveURL = try Fixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(page.utf8),
            "OEBPS/style.css": Data("body { margin: 0; }".utf8),
            "OEBPS/cover.png": Fixture.png()
        ])
        defer { Fixture.remove(archiveURL) }

        let webView = try await Fixture.load(spinePath: "OEBPS/page.xhtml", from: archiveURL)
        defer { Fixture.dismantle(webView) }

        let report = try await Fixture.evaluate(Fixture.probeScript, in: webView) as? String
        let values = Fixture.parse(try #require(report))

        // Item 6: resources internal to the ePub resolve back through the handler. One linked
        // stylesheet survives, the book's own; the remote one does not.
        #expect(values["internal"] != "0")
        #expect(values["sheets"] == "1")
        #expect(values["sheetHrefs"]?.hasSuffix("style.css") == true)

        // Items 1 and 2: the tracking pixel and the remote stylesheet are both blocked.
        #expect(values["remote"] == "0")
        #expect(values["sheetHrefs"]?.contains("example.com") == false)

        // Item 3: a file URL requested from within the document fails.
        #expect(values["local"] == "0")

        // Without the injected viewport meta element WebKit lays out at 980 px.
        #expect(values["innerWidth"] == "\(Int(Fixture.viewportSize.width))")
    }

    /// The end-to-end consequence of the type above: a spine document named `.xml` has to lay out
    /// against the device's width rather than WebKit's 980 px default.
    @MainActor
    @Test func spineDocumentNamedXMLHonoursTheInjectedViewport() async throws {
        let archiveURL = try Fixture.makeArchive(entries: [
            "OPS/main0.xml": Data(Fixture.page(body: "<p>text</p>").utf8)
        ])
        defer { Fixture.remove(archiveURL) }

        let webView = try await Fixture.load(spinePath: "OPS/main0.xml", from: archiveURL)
        defer { Fixture.dismantle(webView) }

        let width = try await Fixture.evaluate("String(window.innerWidth)", in: webView) as? String
        #expect(width == "\(Int(Fixture.viewportSize.width))")
    }

    /// A paged document occupies exactly its viewport vertically and overflows only sideways.
    ///
    /// readium-css sizes a column at `100vh`, which WebKit resolves against the web view's bounds
    /// and not against the area left visible after content insets. A web view that adjusts its
    /// insets automatically therefore lays out a column taller than the area it can show, and the
    /// bottom of every page sits under the chrome until the reader scrolls down to it. The symptom
    /// is a small vertical scroll whose extent is exactly the inset; the cause is the mismatch, so
    /// the host must not add insets a second time.
    @MainActor
    @Test func pagedDocumentDoesNotOverflowVertically() async throws {
        let prose = (1...80)
            .map { "<p>Paragraph \($0). \(String(repeating: "word ", count: 40))</p>" }
            .joined()
        let archiveURL = try Fixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(Fixture.page(body: prose).utf8)
        ])
        defer { Fixture.remove(archiveURL) }

        let webView = try await Fixture.load(
            spinePath: "OEBPS/page.xhtml",
            from: archiveURL,
            insetBehaviour: .never
        )
        defer { Fixture.dismantle(webView) }

        let script = """
        (function() {
            var d = document.documentElement;
            return [
                'innerHeight=' + window.innerHeight,
                'clientHeight=' + d.clientHeight,
                'scrollHeight=' + d.scrollHeight,
                'scrollWidth=' + d.scrollWidth
            ].join('\\n');
        })();
        """
        let report = try await Fixture.evaluate(script, in: webView) as? String
        let values = Fixture.parse(try #require(report))

        #expect(values["scrollHeight"] == values["clientHeight"])
        #expect(values["clientHeight"] == "\(Int(Fixture.viewportSize.height))")

        // Sideways overflow is the whole point, and it lands on a whole number of pages because
        // the column gap is zero.
        let scrollWidth = Int(values["scrollWidth"] ?? "") ?? 0
        #expect(scrollWidth > Int(Fixture.viewportSize.width))
        #expect(scrollWidth % Int(Fixture.viewportSize.width) == 0)
    }

    /// The stopped-task guard. WebKit traps if a completion is delivered to a task it has already
    /// stopped, and an asynchronous provider widens that window rather than narrowing it.
    @MainActor
    @Test func navigatingAwayMidLoadDoesNotTrap() async throws {
        let archiveURL = try Fixture.makeArchive(entries: [
            "OEBPS/first.xhtml": Data(Fixture.page(body: "<p>first</p>").utf8),
            "OEBPS/second.xhtml": Data(Fixture.page(body: "<p>second</p>").utf8)
        ])
        defer { Fixture.remove(archiveURL) }

        let provider = try EpubZipResourceProvider(url: archiveURL)
        let configuration = await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = try Fixture.makeWebView(configuration: configuration)
        defer { Fixture.dismantle(webView) }

        // Replace the navigation before the provider can answer, then abandon that one too.
        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/first.xhtml"))))
        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/second.xhtml"))))
        webView.stopLoading()
        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/first.xhtml"))))

        try await Fixture.waitForDocument(in: webView)

        let body = try await Fixture.evaluate("document.body.textContent.trim()", in: webView) as? String
        #expect(body == "first")
    }

    /// The same document served over the remote provider rather than read out of a zip, which is
    /// the case slice 5 builds on.
    @MainActor
    @Test func spineDocumentRendersThroughTheRemoteProvider() async throws {
        let entries = [
            "OEBPS/page.xhtml": Data(Fixture.page(body: "<p>served</p><img id=\"internal\" src=\"cover.png\"/>").utf8),
            "OEBPS/cover.png": Fixture.png()
        ]
        StubURLProtocol.respond { request in
            let path = String((request.url?.path ?? "").dropFirst())
            guard let data = entries[path] else { return (404, Data()) }
            return (200, data)
        }
        defer { StubURLProtocol.reset() }

        let provider = EpubRemoteResourceProvider(
            baseURL: URL(string: "https://example.test/")!,
            session: StubURLProtocol.session()
        )
        let configuration = await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = try Fixture.makeWebView(configuration: configuration)
        defer { Fixture.dismantle(webView) }

        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/page.xhtml"))))
        try await Fixture.waitForDocument(in: webView)
        try await Fixture.waitForImages(in: webView)

        let body = try await Fixture.evaluate("document.body.textContent.trim()", in: webView) as? String
        #expect(body == "served")

        // The relative image resolves back through the handler and out to the provider as well.
        let width = try await Fixture.evaluate(
            "String(document.getElementById('internal').naturalWidth)",
            in: webView
        ) as? String
        #expect(width == "4")
    }
}

// MARK: - Fixtures

private enum Fixture {
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
    static func png() -> Data {
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format)
        return renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 4, height: 4)))
        }
    }

    static func page(body: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>page</title></head><body>\(body)</body></html>
        """
    }

    @MainActor
    static func makeWebView(configuration: WKWebViewConfiguration) throws -> WKWebView {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: viewportSize), configuration: configuration)
        // The host application's window gives the web view a real viewport, without which the
        // injected meta element has nothing to resolve device-width against.
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        try #require(window).addSubview(webView)
        return webView
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
        let configuration = await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = try makeWebView(configuration: configuration)
        webView.scrollView.contentInsetAdjustmentBehavior = insetBehaviour

        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: spinePath))))
        try await waitForDocument(in: webView)
        try await waitForImages(in: webView)

        return webView
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

    /// The completion-handler form is used deliberately: on current WebKit every content-world
    /// variant of the `async` overload resolves to `()` regardless of what the script returns.
    @MainActor
    static func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script, in: nil, in: EpubWebViewFactory.contentWorld) { result in
                switch result {
                    case .success(let value): continuation.resume(returning: value)
                    case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
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

// MARK: - Stub transport

/// Answers requests in process, so the remote provider can be exercised without a server.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    static func respond(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        Self.handler = handler
    }

    static func reset() {
        handler = nil
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (statusCode, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

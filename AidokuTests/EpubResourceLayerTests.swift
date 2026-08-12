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
        let url = try EpubFixture.makeArchive(entries: ["OEBPS/page.xhtml": Data("hello".utf8)])
        defer { EpubFixture.remove(url) }

        let provider = try EpubZipResourceProvider(url: url)
        let data = try await provider.data(at: "OEBPS/page.xhtml")

        #expect(String(data: data, encoding: .utf8) == "hello")
    }

    @Test func zipProviderToleratesPathVariations() async throws {
        let url = try EpubFixture.makeArchive(entries: [
            "./OEBPS/Chapter One.xhtml": Data("dotted".utf8),
            "OEBPS/Images/Cover.png": Data("cover".utf8)
        ])
        defer { EpubFixture.remove(url) }

        let provider = try EpubZipResourceProvider(url: url)

        // A relative href resolves without the "./" prefix the archive was written with.
        let dotted = try await provider.data(at: "OEBPS/Chapter One.xhtml")
        #expect(String(data: dotted, encoding: .utf8) == "dotted")

        // Case differences are common between the manifest and the archive.
        let lowercased = try await provider.data(at: "oebps/images/cover.png")
        #expect(String(data: lowercased, encoding: .utf8) == "cover")
    }

    @Test func zipProviderThrowsForMissingEntry() async throws {
        let url = try EpubFixture.makeArchive(entries: ["OEBPS/page.xhtml": Data("hello".utf8)])
        defer { EpubFixture.remove(url) }

        let provider = try EpubZipResourceProvider(url: url)

        await #expect(throws: EpubResourceError.self) {
            try await provider.data(at: "OEBPS/missing.xhtml")
        }
    }

    @Test func zipProviderThrowsForUnopenableArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).epub")
        try Data("not a zip".utf8).write(to: url)
        defer { EpubFixture.remove(url) }

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
        let xhtml = Data(EpubFixture.page(body: "<p>text</p>").utf8)
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
        try EpubFixture.png().write(to: localImageURL)
        defer { EpubFixture.remove(localImageURL) }

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
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(page.utf8),
            "OEBPS/style.css": Data("body { margin: 0; }".utf8),
            "OEBPS/cover.png": EpubFixture.png()
        ])
        defer { EpubFixture.remove(archiveURL) }

        let webView = try await EpubFixture.load(spinePath: "OEBPS/page.xhtml", from: archiveURL)
        defer { EpubFixture.dismantle(webView) }

        let report = try await EpubFixture.evaluate(EpubFixture.probeScript, in: webView) as? String
        let values = EpubFixture.parse(try #require(report))

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
        #expect(values["innerWidth"] == "\(Int(EpubFixture.viewportSize.width))")
    }

    /// The end-to-end consequence of the type above: a spine document named `.xml` has to lay out
    /// against the device's width rather than WebKit's 980 px default.
    @MainActor
    @Test func spineDocumentNamedXMLHonoursTheInjectedViewport() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OPS/main0.xml": Data(EpubFixture.page(body: "<p>text</p>").utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let webView = try await EpubFixture.load(spinePath: "OPS/main0.xml", from: archiveURL)
        defer { EpubFixture.dismantle(webView) }

        let width = try await EpubFixture.evaluate("String(window.innerWidth)", in: webView) as? String
        #expect(width == "\(Int(EpubFixture.viewportSize.width))")
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
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: prose).utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let webView = try await EpubFixture.load(
            spinePath: "OEBPS/page.xhtml",
            from: archiveURL,
            insetBehaviour: .never
        )
        defer { EpubFixture.dismantle(webView) }

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
        let report = try await EpubFixture.evaluate(script, in: webView) as? String
        let values = EpubFixture.parse(try #require(report))

        #expect(values["scrollHeight"] == values["clientHeight"])
        #expect(values["clientHeight"] == "\(Int(EpubFixture.viewportSize.height))")

        // Sideways overflow is the whole point, and it lands on a whole number of pages because
        // the column gap is zero.
        let scrollWidth = Int(values["scrollWidth"] ?? "") ?? 0
        #expect(scrollWidth > Int(EpubFixture.viewportSize.width))
        #expect(scrollWidth % Int(EpubFixture.viewportSize.width) == 0)
    }

    /// The stopped-task guard. WebKit traps if a completion is delivered to a task it has already
    /// stopped, and an asynchronous provider widens that window rather than narrowing it.
    @MainActor
    @Test func navigatingAwayMidLoadDoesNotTrap() async throws {
        let archiveURL = try EpubFixture.makeArchive(entries: [
            "OEBPS/first.xhtml": Data(EpubFixture.page(body: "<p>first</p>").utf8),
            "OEBPS/second.xhtml": Data(EpubFixture.page(body: "<p>second</p>").utf8)
        ])
        defer { EpubFixture.remove(archiveURL) }

        let provider = try EpubZipResourceProvider(url: archiveURL)
        let configuration = try await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = try EpubFixture.makeWebView(configuration: configuration)
        defer { EpubFixture.dismantle(webView) }

        // Replace the navigation before the provider can answer, then abandon that one too.
        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/first.xhtml"))))
        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/second.xhtml"))))
        webView.stopLoading()
        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/first.xhtml"))))

        try await EpubFixture.waitForDocument(in: webView)

        let body = try await EpubFixture.evaluate("document.body.textContent.trim()", in: webView) as? String
        #expect(body == "first")
    }

    /// The same document served over the remote provider rather than read out of a zip, which is
    /// the case slice 5 builds on.
    @MainActor
    @Test func spineDocumentRendersThroughTheRemoteProvider() async throws {
        let entries = [
            "OEBPS/page.xhtml": Data(EpubFixture.page(body: "<p>served</p><img id=\"internal\" src=\"cover.png\"/>").utf8),
            "OEBPS/cover.png": EpubFixture.png()
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
        let configuration = try await EpubWebViewFactory.makeConfiguration(provider: provider)
        let webView = try EpubFixture.makeWebView(configuration: configuration)
        defer { EpubFixture.dismantle(webView) }

        webView.load(URLRequest(url: try #require(EpubSchemeHandler.url(forResourcePath: "OEBPS/page.xhtml"))))
        try await EpubFixture.waitForDocument(in: webView)
        try await EpubFixture.waitForImages(in: webView)

        let body = try await EpubFixture.evaluate("document.body.textContent.trim()", in: webView) as? String
        #expect(body == "served")

        // The relative image resolves back through the handler and out to the provider as well.
        let width = try await EpubFixture.evaluate(
            "String(document.getElementById('internal').naturalWidth)",
            in: webView
        ) as? String
        #expect(width == "4")
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

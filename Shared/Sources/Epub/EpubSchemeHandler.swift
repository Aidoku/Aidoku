//
//  EpubSchemeHandler.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import WebKit

/// Serves ePub resources to a `WKWebView` through a custom scheme.
///
/// Nothing is extracted to disk and the web view is never given a filesystem origin. Requests
/// take the shape `aidoku-epub://book/<ePub-internal path>`, so relative links inside a spine
/// document resolve against the same scheme and their subresources arrive here as well. Any path
/// the provider cannot satisfy fails the task; there is no fallback.
@MainActor
final class EpubSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "aidoku-epub"
    nonisolated static let host = "book"

    private let provider: any EpubResourceProvider

    /// The tasks still ours to complete. Delivering a completion to a task WebKit has stopped
    /// traps, and an asynchronous provider widens the window in which that happens. Only touched
    /// on the main thread, where WebKit calls this handler.
    ///
    /// A task is held by its identifier and by the object itself. `ObjectIdentifier` is an address,
    /// and an address belongs to a later object once the one at it is released, so a record kept
    /// under a bare identifier can be read as describing a task it has nothing to do with.
    /// Recording only stopped tasks made that reachable: a request whose provider never returns,
    /// which a stalled `EpubRemoteResourceProvider` fetch is, left its identifier behind for good,
    /// and the next task allocated at that address inherited it and was answered with neither
    /// `didFinish` nor `didFailWithError`. Retaining the object keeps the address its own for as
    /// long as the record lasts, and recording live tasks rather than stopped ones means the record
    /// is cleared by whichever of the two outcomes arrives.
    private var activeTasks: [ObjectIdentifier: any WKURLSchemeTask] = [:]

    init(provider: any EpubResourceProvider) {
        self.provider = provider
    }

    /// The URL under which the web view requests a resource.
    nonisolated static func url(forResourcePath path: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path.hasPrefix("/") ? path : "/" + path
        return components.url
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(EpubResourceError.badRequest)
            return
        }
        let identifier = ObjectIdentifier(urlSchemeTask)
        let path = Self.resourcePath(from: url)
        activeTasks[identifier] = urlSchemeTask

        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await provider.data(at: path)
                guard claimCompletion(of: identifier) else { return }

                let response = URLResponse(
                    url: url,
                    mimeType: Self.mimeType(forPath: path, contents: data),
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard claimCompletion(of: identifier) else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        activeTasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - Helpers

    /// Whether the task is still ours to complete, giving up the claim if it is. A task WebKit has
    /// stopped is no longer held, and so is answered by nobody.
    private func claimCompletion(of identifier: ObjectIdentifier) -> Bool {
        activeTasks.removeValue(forKey: identifier) != nil
    }

    /// URL paths are absolute; ePub-internal paths are not.
    ///
    /// `URL.path` has already decoded the percent encoding, so decoding again would corrupt any
    /// name that legitimately contains a percent sequence: `a%41b.png` is encoded on the way in,
    /// decoded back by `path`, and a second decode would turn it into `aAb.png` and miss the file.
    nonisolated static func resourcePath(from url: URL) -> String {
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        return path
    }

    /// The type a resource is served as.
    ///
    /// The extension decides in every case but one. Some toolchains give spine documents an
    /// `.xml` extension while the package manifest declares them as XHTML, and serving those as
    /// generic XML makes WebKit build an XML document: the viewport meta element is then ignored,
    /// the page lays out at 980 px, and nothing reports an error. The manifest is not available
    /// here, so the contents decide instead.
    nonisolated static func mimeType(forPath path: String, contents: Data = Data()) -> String {
        switch (path as NSString).pathExtension.lowercased() {
            case "xml": declaresXHTML(contents) ? "application/xhtml+xml" : "application/xml"
            case "xhtml", "html", "htm": "application/xhtml+xml"
            case "css": "text/css"
            case "js": "text/javascript"
            case "png": "image/png"
            case "jpg", "jpeg": "image/jpeg"
            case "gif": "image/gif"
            case "webp": "image/webp"
            case "svg": "image/svg+xml"
            case "ttf": "font/ttf"
            case "otf": "font/otf"
            case "woff": "font/woff"
            case "woff2": "font/woff2"
            case "opf", "ncx": "application/xml"
            case "json": "application/json"
            default: "application/octet-stream"
        }
    }

    /// Whether a document names the XHTML namespace, which it does on its root element.
    ///
    /// The namespace is ASCII, so the Latin-1 fallback finds it whatever the document's real
    /// encoding is, including when a multi-byte character straddles the end of the prefix.
    nonisolated private static func declaresXHTML(_ contents: Data) -> Bool {
        let head = contents.prefix(1024)
        let text = String(bytes: head, encoding: .utf8) ?? String(bytes: head, encoding: .isoLatin1)
        return text?.contains("http://www.w3.org/1999/xhtml") ?? false
    }
}

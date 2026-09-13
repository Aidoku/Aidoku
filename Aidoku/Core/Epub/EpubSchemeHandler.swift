//
//  EpubSchemeHandler.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import WebKit

// nothing is extracted to disk, and the web view is never given a file origin
@MainActor
final class EpubSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "aidoku-epub"
    nonisolated static let host = "book"

    private let provider: any EpubResourceProvider

    // delivering to a task WebKit has stopped traps. the task is the value, not just its id:
    // ObjectIdentifier is an address, and a later task can be allocated at a stalled one's
    private var activeTasks: [ObjectIdentifier: any WKURLSchemeTask] = [:]

    init(provider: any EpubResourceProvider) {
        self.provider = provider
    }

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

    private func claimCompletion(of identifier: ObjectIdentifier) -> Bool {
        activeTasks.removeValue(forKey: identifier) != nil
    }

    // URL.path is already decoded; decoding again turns a%41b.png into aAb.png
    nonisolated static func resourcePath(from url: URL) -> String {
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        return path
    }

    // two extensions are not taken at face value: .xml served as generic xml lays out at 980px
    // with no error, and .html may not be well-formed, which the xml parser refuses outright
    nonisolated static func mimeType(forPath path: String, contents: Data = Data()) -> String {
        switch (path as NSString).pathExtension.lowercased() {
            case "xml": declaresXHTML(contents) ? "application/xhtml+xml" : "application/xml"
            case "xhtml": "application/xhtml+xml"
            case "html", "htm": "text/html"
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

    nonisolated private static func declaresXHTML(_ contents: Data) -> Bool {
        let head = contents.prefix(1024)
        let text = String(bytes: head, encoding: .utf8) ?? String(bytes: head, encoding: .isoLatin1)
        return text?.contains("http://www.w3.org/1999/xhtml") ?? false
    }
}

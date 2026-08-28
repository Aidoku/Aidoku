//
//  EpubDocumentLoader.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/28/26.
//

import Foundation
import WebKit

// one spine document in one web view, the arrangement Books and Readium both use. a loader owns its
// renderer for life: moving a web view between hosts is what made the page controller attempt racy
@MainActor
final class EpubDocumentLoader {
    let renderer: EpubSpineRenderer

    private(set) var document: Int?
    private(set) var loadingDocument: Int?
    private(set) var pageCount = 0

    // one task per load, shared by everyone asking for the same document: a request arriving
    // mid-load awaits it rather than starting a second load, which is how a one page document
    // ended up held by two loaders and drawn on both sides of a turn
    private var loadTask: Task<Int, any Error>?

    var webView: WKWebView { renderer.webView }

    var isLoaded: Bool { document != nil }

    var isLoading: Bool { loadTask != nil }

    // what the pool matches against, so a document stays claimed for the whole of its load. the
    // reader's slots go by `document` alone: a web view mid-load still paints whatever it held
    // before, which must not be dragged into view
    var claimedDocument: Int? { document ?? loadingDocument }

    // reports the document it happened in, so a repagination in a preloaded neighbour cannot be
    // recorded against the one being read
    var onRepaginate: ((Int, Int) -> Void)?

    // the document it was holding, which it no longer shows
    var onContentLost: ((Int) -> Void)?

    init(renderer: EpubSpineRenderer) {
        self.renderer = renderer
        renderer.onRepaginate = { [weak self] count in
            guard let self, let document else { return }
            pageCount = count
            onRepaginate?(document, count)
        }
        renderer.onContentProcessTerminated = { [weak self] in
            guard let self, let lost = claimedDocument else { return }
            // released rather than kept: a loader that still claims the document would be handed
            // back for it, and what it shows is a blank page
            prepareForReuse()
            onContentLost?(lost)
        }
    }

    @discardableResult
    func load(document: Int, path: String) async throws -> Int {
        if self.document == document, loadTask == nil {
            return pageCount
        }
        let task: Task<Int, any Error>
        if loadingDocument == document, let running = loadTask {
            task = running
        } else {
            // cleared first: what the web view shows is about to be replaced, and a loader that
            // still claims the old document would be handed back for it
            self.document = nil
            pageCount = 0
            loadingDocument = document
            task = Task { [renderer] in try await renderer.load(spinePath: path) }
            loadTask = task
        }
        do {
            let count = try await task.value
            // applied only while this is still the live load: a later request preempts it by
            // replacing the task, and this one resuming must not clobber that one's state
            if loadTask == task {
                self.document = document
                pageCount = count
                loadingDocument = nil
                loadTask = nil
            }
            return count
        } catch {
            if loadTask == task {
                loadingDocument = nil
                loadTask = nil
            }
            throw error
        }
    }

    func prepareForReuse() {
        loadTask?.cancel()
        loadTask = nil
        loadingDocument = nil
        document = nil
        pageCount = 0
    }
}

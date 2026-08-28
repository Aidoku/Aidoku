//
//  EpubLoaderPool.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/28/26.
//

import Foundation

// a fixed set of loaders recycled between documents, the shape Books keeps under
// ContentLoaderViewReusePool: the document being read, and room for the one on either side
@MainActor
final class EpubLoaderPool {
    var capacity: Int {
        didSet { capacity = max(1, capacity) }
    }

    private(set) var loaders: [EpubDocumentLoader] = []

    private let makeRenderer: () async throws -> EpubSpineRenderer

    var onRepaginate: ((Int, Int) -> Void)?

    // raised before the loader holds a document, so its web view can be put in the hierarchy and
    // have a size by the time one is loaded into it
    var onLoaderCreated: ((EpubDocumentLoader) -> Void)?

    var onContentLost: ((Int) -> Void)?

    // asked at the moment of recycling rather than passed in: a caller that captured which document
    // was being read may have been waiting on a load while the reader turned somewhere else
    var isProtected: ((EpubDocumentLoader) -> Bool)?

    init(capacity: Int = 1, makeRenderer: @escaping () async throws -> EpubSpineRenderer) {
        self.capacity = max(1, capacity)
        self.makeRenderer = makeRenderer
    }

    func loader(holding document: Int) -> EpubDocumentLoader? {
        loaders.first { $0.claimedDocument == document }
    }

    /// The loader holding `document`, loading it into a spare loader or the one furthest from it.
    /// Loaders holding a document in `kept` are left alone.
    func loader(for document: Int, path: String, keeping kept: Set<Int> = []) async throws -> EpubDocumentLoader {
        // holding it already answers at once, holding it mid-load joins that load: either way the
        // document is never loaded a second time, which is what drew it on both sides of a turn
        if let existing = loader(holding: document) {
            try await existing.load(document: document, path: path)
            return try await resolved(existing, for: document, path: path, keeping: kept)
        }
        // an idle loader first: the reader installs a loader's web view when the loader is made, and
        // a renderer that is not in the hierarchy has no size to lay a document out at
        var chosen: EpubDocumentLoader?
        if let idle = loaders.first(where: { !$0.isLoaded && !$0.isLoading }) {
            chosen = idle
        } else if loaders.count < capacity {
            let made = try await make()
            // building a renderer suspends, so the document may have been claimed in the meantime,
            // and loading it into the new loader as well would show it twice
            if let existing = loader(holding: document) {
                try await existing.load(document: document, path: path)
                return try await resolved(existing, for: document, path: path, keeping: kept)
            }
            chosen = made
        }
        let loader = chosen
            ?? recycled(for: document, keeping: kept)
            // every loader is mid-load, so the least useful of them is taken anyway, sparing only
            // the one being read. the load it orphans belongs to a preload, which is reissued
            ?? loaders.first { isProtected?($0) != true }
            ?? loaders[0]
        try await loader.load(document: document, path: path)
        return try await resolved(loader, for: document, path: path, keeping: kept)
    }

    // a loader can be taken over while its load is awaited, so what it holds once the load returns
    // is checked rather than assumed; handing back a loader that holds something else would put the
    // reader's renderer on the wrong document
    private func resolved(
        _ loader: EpubDocumentLoader,
        for document: Int,
        path: String,
        keeping kept: Set<Int>
    ) async throws -> EpubDocumentLoader {
        guard loader.document != document else { return loader }
        return try await self.loader(for: document, path: path, keeping: kept)
    }

    /// An idle loader, built if the pool has room for one. The web view a loader owns has to exist
    /// before the reader can install it, which is earlier than the first document is known.
    @discardableResult
    func prepare() async throws -> EpubDocumentLoader? {
        if let idle = loaders.first(where: { !$0.isLoaded && !$0.isLoading }) {
            return idle
        }
        guard loaders.count < capacity else { return nil }
        return try await make()
    }

    // made on demand rather than up front: a web view per document is only worth its memory once
    // that document is asked for
    private func make() async throws -> EpubDocumentLoader {
        let loader = EpubDocumentLoader(renderer: try await makeRenderer())
        loader.onRepaginate = { [weak self] document, count in self?.onRepaginate?(document, count) }
        loader.onContentLost = { [weak self] document in self?.onContentLost?(document) }
        loaders.append(loader)
        onLoaderCreated?(loader)
        return loader
    }

    /// Drops every loader outside `keep`, freeing the web views they own.
    func release(keeping keep: Set<ObjectIdentifier>) {
        loaders.removeAll { loader in
            guard !keep.contains(ObjectIdentifier(loader.webView)) else { return false }
            loader.prepareForReuse()
            return true
        }
    }

    private func recycled(for document: Int, keeping kept: Set<Int>) -> EpubDocumentLoader? {
        let candidates = loaders.filter { loader in
            guard isProtected?(loader) != true, !loader.isLoading else { return false }
            return loader.claimedDocument.map { !kept.contains($0) } ?? true
        }
        // the furthest from the target is the one least likely to be turned to next
        let furthest = candidates.max { distance(from: $0, to: document) < distance(from: $1, to: document) }
        // every loader busy is possible while several documents are in flight, and taking one of
        // them would orphan its load, so a new one is worth going a little over capacity for
        guard let loader = furthest else { return nil }
        loader.prepareForReuse()
        return loader
    }

    private func distance(from loader: EpubDocumentLoader, to document: Int) -> Int {
        guard let held = loader.claimedDocument else { return .max }
        return abs(held - document)
    }
}

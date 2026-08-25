//
//  EpubSpineMeasurer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import WebKit

// counts every spine document in the background, reporting each as it lands. it counts at load and
// never calls settle(), which cost a flat 507 to 514ms per document and changed no count at all.
// its web view needs a frame and a layout but never a view hierarchy
@MainActor
final class EpubSpineMeasurer {
    struct Outcome {
        let measured: Int
        // spine paths that could not be laid out, in spine order
        let failed: [String]
        // true when the pass was cancelled or superseded rather than reaching the end
        let cancelled: Bool
    }

    private struct Reports {
        let count: (Int, Int) -> Void
        let failure: (Int) -> Void
        let finish: (Outcome) -> Void
    }

    private let provider: any EpubResourceProvider
    private let settings: EpubPaginationSettings

    // built on the first pass and kept afterwards. its configuration carries a scheme handler bound
    // to one provider, so a measurer serves the book it was made for
    private var renderer: EpubSpineRenderer?
    private var task: Task<Void, Never>?

    // checked between documents, so a pause takes effect within one document rather than at once
    private var isPaused = false

    private static let pausePollNanoseconds: UInt64 = 20_000_000

    // so a pass finishing can tell whether it is still the one whose task is stored, rather than
    // clearing a successor's
    private var generation = 0

    var isMeasuring: Bool {
        guard let task else { return false }
        return !task.isCancelled
    }

    init(provider: any EpubResourceProvider, settings: EpubPaginationSettings = .default) {
        self.provider = provider
        self.settings = settings
    }

    deinit {
        task?.cancel()
    }

    // walked in order because a position needs every earlier document counted, so measuring
    // forwards makes the reader's own position available soonest. skipping holds positions already
    // counted, which is at least the document the reader has open. cancels any pass already running
    func start(
        spinePaths: [String],
        viewport: CGSize,
        skipping: Set<Int> = [],
        onCount: @escaping (Int, Int) -> Void,
        onFailure: @escaping (Int) -> Void = { _ in },
        onFinish: @escaping (Outcome) -> Void
    ) {
        let superseded = task
        cancel()

        self.generation += 1
        let generation = self.generation

        guard !spinePaths.isEmpty, viewport.width > 0, viewport.height > 0 else {
            onFinish(Outcome(measured: 0, failed: [], cancelled: false))
            return
        }

        task = Task { [weak self] in
            // the renderer is shared across passes and tracks one navigation at a time, so two
            // passes in the same web view file counts under each other's paths, which showed up on
            // a 217 document book as a total seven pages long. waiting removes the overlap
            await superseded?.value
            guard let self, !Task.isCancelled else {
                // every other exit reports an outcome, so a caller waiting on onFinish would
                // otherwise wait for ever on a pass replaced while it queued
                onFinish(Outcome(measured: 0, failed: [], cancelled: true))
                return
            }
            await run(
                spinePaths: spinePaths,
                viewport: viewport,
                skipping: skipping,
                reports: Reports(count: onCount, failure: onFailure, finish: onFinish)
            )
            // cleared only while it is still the current pass, since a later one may have replaced
            // it in the meantime
            if self.generation == generation {
                self.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // provider reads serialise onto one file handle, so a pass and a reader contend for them. a
    // reader waiting on a background count is a visible stall; the reverse is not
    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    private func run(
        spinePaths: [String],
        viewport: CGSize,
        skipping: Set<Int>,
        reports: Reports
    ) async {
        let renderer: EpubSpineRenderer
        do {
            renderer = try await makeRenderer()
        } catch {
            LogManager.logger.error("EpubSpineMeasurer: could not build a renderer: \(error)")
            // reported one by one as well as in the outcome, so a caller placing failures in an
            // index needs no second route for a pass that never started
            for index in spinePaths.indices { reports.failure(index) }
            reports.finish(Outcome(measured: 0, failed: spinePaths, cancelled: false))
            return
        }

        guard !Task.isCancelled else {
            reports.finish(Outcome(measured: 0, failed: [], cancelled: true))
            return
        }

        renderer.webView.frame = CGRect(origin: .zero, size: viewport)
        // laid out immediately, since the first document is loaded before a detached view would
        // otherwise adopt the frame, and a view at its default zero size reports a meaningless
        // viewport
        renderer.webView.layoutIfNeeded()

        var measured = 0
        var failed: [String] = []

        for (index, path) in spinePaths.enumerated() {
            guard !Task.isCancelled else {
                reports.finish(Outcome(measured: measured, failed: failed, cancelled: true))
                return
            }
            guard !skipping.contains(index) else { continue }

            while isPaused && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pausePollNanoseconds)
            }

            do {
                let count = try await renderer.load(spinePath: path)
                // checked after the load as well as before it: a pass superseded mid-load measured
                // the document at a viewport that no longer applies
                guard !Task.isCancelled else {
                    reports.finish(Outcome(measured: measured, failed: failed, cancelled: true))
                    return
                }
                measured += 1
                reports.count(index, count)
            } catch {
                // what a book with an unreadable document should show as its total is the caller's
                // decision, not this type's
                LogManager.logger.error("EpubSpineMeasurer: could not lay out \(path): \(error)")
                failed.append(path)
                reports.failure(index)
            }

            // between documents, so a reader waiting on the provider is not held for a whole spine
            await Task.yield()
        }

        reports.finish(Outcome(measured: measured, failed: failed, cancelled: false))
    }

    private func makeRenderer() async throws -> EpubSpineRenderer {
        if let renderer { return renderer }
        let renderer = try await EpubSpineRenderer(provider: provider, settings: settings)
        self.renderer = renderer
        return renderer
    }
}

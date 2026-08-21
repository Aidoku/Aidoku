//
//  EpubSpineMeasurer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import WebKit

/// Counts the pages of every spine document of a book, in the background, while it is being read.
///
/// One ePub is one chapter, so the reader's page counter and slider describe a whole book, and a
/// book's total is the sum of counts that only exist once each document has been laid out. This
/// walks the spine and produces them. It does not hold the counts; `EpubPageIndex` does, and this
/// reports each one as it lands so a caller can decide what a partial total means.
///
/// **It counts at `load` and never calls `settle()`.** Measured across 53 documents of the two most
/// illustrated books in the corpus: settling costs a flat 507 to 514 ms per document, being
/// `holdCurrentPage`'s half-second window, and it changed no count at all. Every count taken at
/// `didFinish` already equalled the settled one. Settling would turn a four-second pass into half a
/// minute and buy nothing. Images cost little for the same reason, 39 ms against 22 ms for
/// text-only documents on the most illustrated book and inside the noise on the next.
///
/// **Its web view is never added to a view hierarchy.** A frame and a layout are what a viewport
/// needs; window membership is not. Verified by loading one document into a view installed in the
/// key window, a detached view with a frame, one at `alpha` zero and one hidden, all four of which
/// reported the same count, viewport and scroll width. A walk of 217 documents on a detached view
/// then reported correct counts throughout with no failures.
///
/// **A pass belongs to a viewport.** A count describes a document laid out at a size, so a size
/// change cancels the pass in flight and starts another. Nothing measured under the old size may be
/// published afterwards, which is why cancellation is checked after each load rather than only
/// before it.
@MainActor
final class EpubSpineMeasurer {
    /// What a finished pass did, whether or not it ran to the end.
    struct Outcome {
        /// Documents whose count was measured and published by this pass.
        let measured: Int
        /// Spine paths that could not be laid out, in spine order.
        let failed: [String]
        /// True when the pass was cancelled or superseded rather than reaching the end.
        let cancelled: Bool
    }

    /// The three ways a pass reports, bundled so that handing them on stays one argument.
    private struct Reports {
        let count: (Int, Int) -> Void
        let failure: (Int) -> Void
        let finish: (Outcome) -> Void
    }

    private let provider: any EpubResourceProvider
    private let settings: EpubPaginationSettings

    /// Built on the first pass and kept afterwards.
    ///
    /// Its configuration carries a scheme handler bound to one provider and therefore to one book,
    /// so a measurer serves the book it was made for. Keeping it costs one idle web view: walking a
    /// whole spine moved peak footprint by +0.6 MB in stage 1, because the view is reused rather
    /// than made per document.
    private var renderer: EpubSpineRenderer?
    private var task: Task<Void, Never>?

    /// Checked between documents, so a pause takes effect within one document rather than at once.
    private var isPaused = false

    /// How long to wait before looking at `isPaused` again.
    ///
    /// A poll rather than a continuation, matching the renderer, where polling was judged
    /// preferable to running a state machine against WebKit's callbacks. At this interval the cost
    /// is immaterial next to the load it is waiting for.
    private static let pausePollNanoseconds: UInt64 = 20_000_000

    /// Which pass is current, so that a pass finishing can tell whether it is still the one whose
    /// task is stored, rather than clearing a successor's.
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

    /// Walks `spinePaths` in order, reporting each count through `onCount` as it lands.
    ///
    /// In order because a position in a book needs every *earlier* document counted: the answers
    /// `EpubPageIndex` gives become available from the front of the spine, so measuring forwards
    /// makes the reader's own position available soonest.
    ///
    /// `skipping` holds spine positions whose count is already known, which is at least the
    /// document the reader has open, since the reading renderer measured it on the way in. Cancels
    /// any pass already running.
    ///
    /// `onFailure` reports a document that could not be laid out, by spine position, as the failure
    /// happens rather than at the end of the pass. Every answer about a position *after* that
    /// document waits on whatever the caller decides to do about it, so it is worth telling them at
    /// once rather than after the remaining documents have been walked.
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
            // A cancelled pass is not a finished one. Cancellation is cooperative and the pass is
            // suspended inside `renderer.load`, which it keeps waiting on; the renderer is reused
            // across passes, and it tracks one navigation at a time. Loading into the same web view
            // while the old load is still settling therefore makes the two indistinguishable: one
            // of them is resumed with `superseded` and its document is recorded as unmeasurable,
            // while the other measures whichever document the web view ended up holding and files
            // that count under its own path. Both were seen on a 217 document book opened at a size
            // that settled after the first pass had begun, as a total seven pages long and as one a
            // document short. Waiting for the old pass to leave the renderer costs one document's
            // load, a 9 ms median, and removes the overlap rather than detecting it.
            await superseded?.value
            guard let self, !Task.isCancelled else {
                // Every other exit from a pass reports an outcome. A caller that waits on
                // `onFinish`, which is how the tests observe a pass, would otherwise wait for ever
                // on one that was replaced while it queued behind the pass before it.
                onFinish(Outcome(measured: 0, failed: [], cancelled: true))
                return
            }
            await run(
                spinePaths: spinePaths,
                viewport: viewport,
                skipping: skipping,
                reports: Reports(count: onCount, failure: onFailure, finish: onFinish)
            )
            // A pass that has run to completion is no longer measuring. Cleared only while it is
            // still the current one, since a later pass may have replaced it in the meantime.
            if self.generation == generation {
                self.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Suspends the pass between documents.
    ///
    /// Provider reads serialise onto one file handle, so a pass and a reader contend for them. A
    /// page turn that stays within a loaded document never touches the provider and needs no pause;
    /// one that crosses into another spine document does, and is worth pausing around, since a
    /// reader waiting on a background count is a visible stall while a count waiting on a reader is
    /// invisible.
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
            // Reported one by one as well as in the outcome: every path this pass gives up on
            // reaches `onFailure`, so a caller placing failures in an index does not need a second
            // route for the case where the pass never started.
            for index in spinePaths.indices { reports.failure(index) }
            reports.finish(Outcome(measured: 0, failed: spinePaths, cancelled: false))
            return
        }

        guard !Task.isCancelled else {
            reports.finish(Outcome(measured: 0, failed: [], cancelled: true))
            return
        }

        // Set once per pass rather than per document. The count itself is read from the document,
        // as `scrollWidth` over `innerWidth`, so this size is what the document is laid out at
        // rather than a width any arithmetic here depends on.
        renderer.webView.frame = CGRect(origin: .zero, size: viewport)
        // Laid out immediately rather than at the next pass, since the first document is loaded
        // before a detached view would otherwise be given a chance to adopt the frame, and a view
        // still at its default zero size reports a viewport that means nothing.
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
                // Checked after the load as well as before it. A pass superseded while this
                // document was loading measured it at a viewport that no longer applies, and
                // publishing that count would put a stale number into the index the new pass is
                // filling.
                guard !Task.isCancelled else {
                    reports.finish(Outcome(measured: measured, failed: failed, cancelled: true))
                    return
                }
                measured += 1
                reports.count(index, count)
            } catch {
                // A document that cannot be laid out cannot be read either, so this is reported
                // rather than substituted for. What a book with an unreadable document should show
                // as its total is the caller's decision, not this type's.
                LogManager.logger.error("EpubSpineMeasurer: could not lay out \(path): \(error)")
                failed.append(path)
                reports.failure(index)
            }

            // Between documents, so a reader waiting on the provider is not held for the length of
            // a whole spine.
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

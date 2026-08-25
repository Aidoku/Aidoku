//
//  EpubSpineMeasurer.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/13/26.
//

import Foundation
import WebKit

// counts every spine document in the background, reporting each as it lands. counts at load
// without settling, which cost ~510ms a document and changed no count. the web view needs a frame
// and a layout, never a view hierarchy
@MainActor
final class EpubSpineMeasurer {
    struct Outcome {
        let measured: Int
        // spine paths that could not be laid out, in spine order
        let failed: [String]
        // cancelled or superseded rather than having reached the end
        let cancelled: Bool
    }

    private struct Reports {
        let count: (Int, Int) -> Void
        let failure: (Int) -> Void
        let finish: (Outcome) -> Void
    }

    private let provider: any EpubResourceProvider
    private let settings: EpubPaginationSettings

    // its configuration binds one provider, so a measurer serves the book it was made for
    private var renderer: EpubSpineRenderer?
    private var task: Task<Void, Never>?

    private var isPaused = false

    private static let pausePollNanoseconds: UInt64 = 20_000_000

    // so a finishing pass does not clear a successor's task
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

    // walked in order, a position needing every earlier document counted. cancels any running pass
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
            // the renderer tracks one navigation, so overlapping passes file counts under each
            // other's paths; waiting removes the overlap rather than detecting it
            await superseded?.value
            guard let self, !Task.isCancelled else {
                // every other exit reports an outcome, so a queued-then-replaced pass must too
                onFinish(Outcome(measured: 0, failed: [], cancelled: true))
                return
            }
            await run(
                spinePaths: spinePaths,
                viewport: viewport,
                skipping: skipping,
                reports: Reports(count: onCount, failure: onFailure, finish: onFinish)
            )
            // only while still the current pass
            if self.generation == generation {
                self.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // provider reads serialise onto one file handle, so a reader and this pass contend
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
            // one by one as well as in the outcome, so a pass that never started needs no second route
            for index in spinePaths.indices { reports.failure(index) }
            reports.finish(Outcome(measured: 0, failed: spinePaths, cancelled: false))
            return
        }

        guard !Task.isCancelled else {
            reports.finish(Outcome(measured: 0, failed: [], cancelled: true))
            return
        }

        renderer.webView.frame = CGRect(origin: .zero, size: viewport)
        // a detached view would not adopt the frame before the first load, and a zero-size view
        // reports a meaningless viewport
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
                // after the load too: a pass superseded mid-load measured a stale viewport
                guard !Task.isCancelled else {
                    reports.finish(Outcome(measured: measured, failed: failed, cancelled: true))
                    return
                }
                measured += 1
                reports.count(index, count)
            } catch {
                // what an unreadable document does to the total is the caller's decision
                LogManager.logger.error("EpubSpineMeasurer: could not lay out \(path): \(error)")
                failed.append(path)
                reports.failure(index)
            }

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

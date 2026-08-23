//
//  DictionaryTextAnalysisScheduler.swift
//  Aidoku
//
//  Created by skitty on 7/19/26.
//

import UIKit

@available(iOS 18.0, *)
private actor DictionaryTextAnalysisQueue {
    static let shared = DictionaryTextAnalysisQueue()

    private var isRunning = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitForTurn() async {
        if !isRunning {
            isRunning = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finishTurn() {
        if waiters.isEmpty {
            isRunning = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func run(_ operation: () async -> Void) async {
        await waitForTurn()
        await operation()
        finishTurn()
    }
}

@available(iOS 18.0, *)
enum DictionaryTextAnalysisScheduler {
    static func cancel(
        task: inout Task<Void, Never>?,
        recognizer: TextRecognizer?
    ) {
        task?.cancel()
        task = nil
        recognizer?.reset()
    }

    static func schedule(
        task: inout Task<Void, Never>?,
        recognizer: inout TextRecognizer?,
        image: UIImage?,
        language: String?,
        onFinish: @MainActor @escaping () -> Void
    ) {
        task?.cancel()
        guard
            AppSettings.dictionary.isOCREnabled(language: language),
            let image
        else {
            recognizer?.reset()
            task = nil
            return
        }

        let runRecognizer = TextRecognizer()
        recognizer = runRecognizer
        task = Task { [weak runRecognizer] in
            await DictionaryTextAnalysisQueue.shared.run {
                guard !Task.isCancelled, let runRecognizer else { return }
                await runRecognizer.analyze(image, language: language)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    onFinish()
                }
            }
        }
    }
}

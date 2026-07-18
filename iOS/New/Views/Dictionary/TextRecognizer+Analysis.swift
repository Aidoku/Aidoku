//
//  TextRecognizer+Analysis.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import Vision

@available(iOS 18.0, *)
extension TextRecognizer {
    func analyze(_ image: UIImage, language: String?) async {
        guard let cgImage = image.cgImage else { return }
        let recognizedObservations = await recognizeObservations(in: cgImage, language: language)
        guard !Task.isCancelled else { return }
        observations = recognizedObservations
        rebuildClusterCache()
    }

    private func recognizeObservations(in cgImage: CGImage, language: String?) async -> [OCRObservation] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        if let language {
            request.recognitionLanguages = [Locale.Language(identifier: language)]
        }
        let restrictOCRLanguages = AppSettings.dictionary.restrictOCRLanguages.get()
        request.automaticallyDetectsLanguage = !restrictOCRLanguages
        request.usesLanguageCorrection = true

        let results = (try? await request.perform(on: cgImage)) ?? []
        return results.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let characters = recognizedCharacters(from: candidate)
            let text = characters.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !characters.isEmpty else { return nil }
            return .init(
                text: text,
                boundingRect: observation.boundingBox.cgRect,
                direction: {
                    if #available(iOS 26.0, *) {
                        switch observation.textDirection {
                        case .topToBottom:
                            return .topToBottom
                        case .leftToRight:
                            return .leftToRight
                        case .rightToLeft:
                            return .rightToLeft
                        case .none:
                            return .unknown
                        @unknown default:
                            return .unknown
                        }
                    } else {
                        return .unknown
                    }
                }(),
                confidence: candidate.confidence,
                characters: characters
            )
        }
    }

    private func recognizedCharacters(from candidate: RecognizedText) -> [OCRCharacter] {
        let rawText = candidate.string
        guard !rawText.isEmpty else { return [] }

        var characters: [OCRCharacter] = []
        characters.reserveCapacity(rawText.count)
        for index in rawText.indices {
            let char = rawText[index]
            if char == "\n" || char == "\r" { continue }
            let range = index..<rawText.index(after: index)
            guard let box = candidate.boundingBox(for: range) else { continue }
            characters.append(.init(text: String(char), boundingRect: box.boundingBox.cgRect))
        }
        return characters
    }
}

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
            await DictionaryTextAnalysisQueue.shared.waitForTurn()
            defer { await DictionaryTextAnalysisQueue.shared.finishTurn() }

            guard !Task.isCancelled, let runRecognizer else { return }
            await runRecognizer.analyze(image, language: language)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onFinish()
            }
        }
    }
}

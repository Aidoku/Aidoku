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
    func analyze(_ image: UIImage) async {
        guard let cgImage = image.cgImage else { return }
        let preprocessedImage = preprocessForOCR(cgImage)
        let recognizedObservations = await recognizeObservations(in: preprocessedImage)
        guard !Task.isCancelled else { return }
        observations = recognizedObservations
        rebuildClusterCache()
#if DEBUG
        debugDumpClusters()
#endif
    }

    private func recognizeObservations(in cgImage: CGImage) async -> [OCRObservation] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        let selectedLanguage = UserDefaults.standard.string(forKey: "Reader.dictionaryOCRLanguage") ?? "ja"
        request.recognitionLanguages = switch selectedLanguage {
        case "zh":
            [Locale.Language(identifier: "zh-Hans")]
        case "ko":
            [Locale.Language(identifier: "ko")]
        default:
            [Locale.Language(identifier: "ja")]
        }
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

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

    private func preprocessForOCR(_ cgImage: CGImage) -> CGImage {
        guard UserDefaults.standard.bool(forKey: "Reader.dictionaryOCRPreUpscale") else { return cgImage }
        guard !UserDefaults.standard.bool(forKey: "Reader.upscaleImages") else { return cgImage }
        return preprocessForOCRPlain(cgImage)
    }

    private func preprocessForOCRPlain(_ cgImage: CGImage) -> CGImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let longestSide = max(width, height)

        // Improve tiny glyph recognition by upscaling smaller pages before OCR.
        let targetLongestSide: CGFloat = 2800
        let scaleFactor = min(2.0, max(1.0, targetLongestSide / longestSide))
        guard scaleFactor > 1.05 else { return cgImage }

        let scaledSize = CGSize(width: width * scaleFactor, height: height * scaleFactor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: scaledSize, format: format)
        let image = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: scaledSize))
        }
        return image.cgImage ?? cgImage
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
        onFinish: @MainActor @escaping () -> Void
    ) {
        task?.cancel()
        guard UserDefaults.standard.bool(forKey: "Reader.dictionary"),
              LookupEngine.shared.isReady,
              let image else {
            recognizer?.reset()
            task = nil
            return
        }

        let runRecognizer = TextRecognizer()
        recognizer = runRecognizer
        task = Task { [weak runRecognizer] in
            guard !Task.isCancelled, let runRecognizer else { return }
            await runRecognizer.analyze(image)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onFinish()
            }
        }
    }
}

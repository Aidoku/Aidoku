//
//  TextRecognizer+Analysis.swift
//  Aidoku (iOS)
//
//  Created by GameFuzzy on 7/11/26.
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
            guard
                let candidate = observation.topCandidates(1).first,
                case let characters = recognizedCharacters(from: candidate),
                case let text = characters.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty, !characters.isEmpty
            else {
                return nil
            }
            return .init(
                text: text,
                boundingRect: observation.boundingBox.cgRect,
                direction: {
                    if #available(iOS 26.0, *) {
                        switch observation.textDirection {
                            case .topToBottom: return .topToBottom
                            case .leftToRight: return .leftToRight
                            case .rightToLeft: return .rightToLeft
                            case .none: return .unknown
                            @unknown default: return .unknown
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

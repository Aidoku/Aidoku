//
//  TextRecognizer+Lookup.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@available(iOS 18.0, *)
extension TextRecognizer {
    func findText(at viewPoint: CGPoint, in imageView: UIView, imageSize: CGSize) -> Result? {
        guard let normalizedPoint = normalizedImagePoint(viewPoint, in: imageView, imageSize: imageSize) else {
            return nil
        }
        let sourceObservations: [(offset: Int, element: OCRObservation)] = Array(observations.enumerated())
        guard !sourceObservations.isEmpty else { return nil }

        let hitCandidates = sourceObservations.filter { $0.element.boundingRect.contains(normalizedPoint) }

        let primary: (offset: Int, element: OCRObservation)? = hitCandidates.min { lhs, rhs in
            let lhsArea = lhs.element.boundingRect.width * lhs.element.boundingRect.height
            let rhsArea = rhs.element.boundingRect.width * rhs.element.boundingRect.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            if lhs.element.confidence != rhs.element.confidence {
                return lhs.element.confidence > rhs.element.confidence
            }
            return lhs.offset < rhs.offset
        }

        guard let (primaryIndex, primaryObservation) = primary else {
            return nil
        }
        let primaryCharacters = primaryObservation.characters
        guard !primaryCharacters.isEmpty else { return nil }
        guard let bestOffset = primaryCharacters.firstIndex(where: { $0.boundingRect.contains(normalizedPoint) }) else { return nil }
        let anchorRect = viewRect(from: primaryObservation.boundingRect, in: imageView, imageSize: imageSize)

        let orderedCluster = orderedClusterForObservation(primaryIndex) ?? [primaryIndex]

        var lookupSlice = ""
        var charRects: [CGRect] = []
        var includeFromCurrent = false

        for clusterIndex in orderedCluster {
            let clusterObservation = observations[clusterIndex]
            let text = clusterObservation.text
            guard !text.isEmpty else { continue }

            let startOffset: Int
            if clusterIndex == primaryIndex {
                includeFromCurrent = true
                startOffset = bestOffset
            } else if includeFromCurrent {
                startOffset = 0
            } else {
                continue
            }

            guard startOffset < clusterObservation.characters.count else { continue }

            let startIndex = text.index(text.startIndex, offsetBy: startOffset)
            lookupSlice += String(text[startIndex...])

            for character in clusterObservation.characters[startOffset...] {
                charRects.append(viewRect(from: character.boundingRect, in: imageView, imageSize: imageSize))
            }
        }

        let contextText = orderedCluster
            .map { observations[$0].text }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            text: lookupSlice,
            fullText: contextText.isEmpty ? primaryObservation.text : contextText,
            charRect: anchorRect,
            charRects: charRects
        )
    }

    func paragraphOverlays(in imageView: UIView, imageSize: CGSize) -> [ParagraphOverlay] {
        let clusters = clusterIndices()
        guard !clusters.isEmpty else { return [] }

        return clusters.compactMap { cluster -> ParagraphOverlay? in
            let indices = orderedClusterIndices(cluster)

            var mergedRect: CGRect = .null
            for index in indices {
                mergedRect = mergedRect.union(observations[index].boundingRect)
            }

            guard !mergedRect.isNull, !mergedRect.isEmpty else { return nil }
            let overlayRect = viewRect(from: mergedRect, in: imageView, imageSize: imageSize)
            guard overlayRect.width > 12, overlayRect.height > 8 else { return nil }

            struct SegmentBuild {
                let text: String
                let rect: CGRect
                let charRects: [CGRect]
            }

            let segmentBuilds = indices.compactMap { index -> SegmentBuild? in
                let observation = observations[index]
                let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let rect = viewRect(from: observation.boundingRect, in: imageView, imageSize: imageSize)
                guard !rect.isNull, !rect.isEmpty else { return nil }
                let charRects = observation.characters.map { viewRect(from: $0.boundingRect, in: imageView, imageSize: imageSize) }
                guard !charRects.isEmpty else { return nil }
                return .init(text: text, rect: rect, charRects: charRects)
            }

            let mergedText = segmentBuilds.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mergedText.isEmpty else { return nil }

            var currentOffset = 0
            let segments = segmentBuilds.map { segment -> ParagraphOverlay.Segment in
                let startOffset = currentOffset
                currentOffset += segment.text.count

                let charHits = segment.charRects.enumerated().compactMap { idx, rect -> ParagraphOverlay.CharHit? in
                    let globalOffset = startOffset + idx
                    guard globalOffset < mergedText.count else { return nil }
                    let sliceStart = mergedText.index(mergedText.startIndex, offsetBy: globalOffset)
                    let slice = String(mergedText[sliceStart...])
                    guard !slice.isEmpty else { return nil }
                    return .init(text: slice, rect: rect)
                }

                return .init(text: segment.text, rect: segment.rect, charHits: charHits)
            }

            return ParagraphOverlay(
                text: mergedText,
                rect: overlayRect.insetBy(dx: -2, dy: -1),
                segments: segments
            )
        }
    }

    private func normalizedImagePoint(_ viewPoint: CGPoint, in imageView: UIView, imageSize: CGSize) -> CGPoint? {
        let viewSize = imageView.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return nil }

        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2

        let imageRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)
        guard imageRect.contains(viewPoint) else { return nil }

        let normalizedX = (viewPoint.x - imageRect.origin.x) / imageRect.width
        let normalizedY = 1 - (viewPoint.y - imageRect.origin.y) / imageRect.height

        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private func viewRect(from normalizedRect: CGRect, in imageView: UIView, imageSize: CGSize) -> CGRect {
        let viewSize = imageView.bounds.size

        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)

        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (viewSize.width - scaledWidth) / 2
        let offsetY = (viewSize.height - scaledHeight) / 2

        let x = offsetX + normalizedRect.origin.x * scaledWidth
        let y = offsetY + (1 - normalizedRect.origin.y - normalizedRect.height) * scaledHeight
        let width = normalizedRect.width * scaledWidth
        let height = normalizedRect.height * scaledHeight

        return CGRect(x: x, y: y, width: width, height: height)
    }

}

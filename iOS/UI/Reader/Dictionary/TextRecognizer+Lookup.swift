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

        guard let (primaryIndex, primaryObservation) = primary,
              let candidate = primaryObservation.observation.topCandidates(1).first else {
            return nil
        }

        let pressedObservationText = candidate.string
        guard !pressedObservationText.isEmpty else { return nil }

        var bestIndex: String.Index?
        for i in pressedObservationText.indices {
            let range = i..<pressedObservationText.index(after: i)
            guard let charObs = candidate.boundingBox(for: range) else { continue }
            let charBox = charObs.boundingBox.cgRect
            if charBox.contains(normalizedPoint) {
                bestIndex = i
                break
            }
        }

        guard let bestIndex else { return nil }

        let firstCharRange = bestIndex..<pressedObservationText.index(after: bestIndex)
        guard candidate.boundingBox(for: firstCharRange) != nil else { return nil }
        let anchorRect = viewRect(from: primaryObservation.boundingRect, in: imageView, imageSize: imageSize)

        let cluster = clusterIndices().first(where: { $0.contains(primaryIndex) }) ?? [primaryIndex]
        let orderedCluster = orderedClusterIndices(cluster)

        var lookupSlice = ""
        var charRects: [CGRect] = []
        var includeFromCurrent = false

        for clusterIndex in orderedCluster {
            guard let clusterCandidate = observations[clusterIndex].observation.topCandidates(1).first else { continue }
            let text = clusterCandidate.string
            guard !text.isEmpty else { continue }

            let startIndex: String.Index
            if clusterIndex == primaryIndex {
                includeFromCurrent = true
                startIndex = bestIndex
            } else if includeFromCurrent {
                startIndex = text.startIndex
            } else {
                continue
            }

            lookupSlice += String(text[startIndex...])
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")

            for idx in text[startIndex...].indices {
                let range = idx..<text.index(after: idx)
                if let obs = clusterCandidate.boundingBox(for: range) {
                    charRects.append(viewRect(from: obs.boundingBox.cgRect, in: imageView, imageSize: imageSize))
                }
            }
        }

        let contextText = orderedCluster
            .map { observations[$0].text }
            .map {
                $0
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(
            text: lookupSlice,
            fullText: contextText.isEmpty ? pressedObservationText : contextText,
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
                guard let candidate = observations[index].observation.topCandidates(1).first else { return nil }
                let rawText = candidate.string
                guard !rawText.isEmpty else { return nil }

                var chars: [String] = []
                var charRects: [CGRect] = []
                for i in rawText.indices {
                    let char = rawText[i]
                    if char == "\n" || char == "\r" { continue }
                    let range = i..<rawText.index(after: i)
                    guard let box = candidate.boundingBox(for: range) else { continue }
                    chars.append(String(char))
                    charRects.append(viewRect(from: box.boundingBox.cgRect, in: imageView, imageSize: imageSize))
                }

                let text = chars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let rect = viewRect(from: observations[index].boundingRect, in: imageView, imageSize: imageSize)
                guard !rect.isNull, !rect.isEmpty else { return nil }
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

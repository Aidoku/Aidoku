//
//  TextRecognizer.swift
//  Aidoku (iOS)
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import Vision

@available(iOS 18.0, *)
class TextRecognizer {
    enum ReadingOrientation {
        case vertical
        case leftToRight
        case rightToLeft
    }

    enum ObservationDirection {
        case topToBottom
        case leftToRight
        case rightToLeft
        case unknown
    }

    struct OCRCharacter {
        let text: String
        let boundingRect: CGRect
    }

    struct OCRObservation {
        let text: String
        let boundingRect: CGRect
        let direction: ObservationDirection
        let confidence: Float
        let characters: [OCRCharacter]
    }

    struct Result {
        let text: String
        let fullText: String
        var charRect: CGRect
        var charRects: [CGRect]
    }

    struct ParagraphOverlay {
        struct CharHit {
            let text: String
            let rect: CGRect
        }

        struct Segment {
            let text: String
            let rect: CGRect
            let charHits: [CharHit]
        }

        let text: String
        let rect: CGRect
        let segments: [Segment]
    }

    var observations: [OCRObservation] = []
    var cachedClusters: [[Int]] = []
    var cachedOrderedClusters: [[Int]] = []
    var clusterIndexByObservation: [Int: Int] = [:]

    func reset() {
        observations = []
        cachedClusters = []
        cachedOrderedClusters = []
        clusterIndexByObservation = [:]
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

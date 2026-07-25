//
//  TextRecognizer+Clustering.swift
//  Aidoku (iOS)
//
//  Created by GameFuzzy on 7/11/26.
//

import UIKit

@available(iOS 18.0, *)
extension TextRecognizer {
    func rebuildClusterCache() {
        guard !observations.isEmpty else {
            cachedClusters = []
            cachedOrderedClusters = []
            clusterIndexByObservation = [:]
            return
        }

        let clusters = computeClusterIndices()
        cachedClusters = clusters
        cachedOrderedClusters = clusters.map(orderedClusterIndicesUncached)

        var indexMap: [Int: Int] = [:]
        for (clusterIndex, cluster) in clusters.enumerated() {
            for observationIndex in cluster {
                indexMap[observationIndex] = clusterIndex
            }
        }
        clusterIndexByObservation = indexMap
    }

    func orderedClusterForObservation(_ index: Int) -> [Int]? {
        guard
            let clusterIndex = clusterIndexByObservation[index],
            cachedOrderedClusters.indices.contains(clusterIndex)
        else {
            return nil
        }
        return cachedOrderedClusters[clusterIndex]
    }

    func orderedClusterIndices(_ indices: [Int]) -> [Int] {
        if
            let clusterIndex = cachedClusters.firstIndex(where: { $0 == indices }),
            cachedOrderedClusters.indices.contains(clusterIndex)
        {
            return cachedOrderedClusters[clusterIndex]
        }
        return orderedClusterIndicesUncached(indices)
    }

    private func orderedClusterIndicesUncached(_ indices: [Int]) -> [Int] {
        guard !indices.isEmpty else { return [] }

        let orientation = clusterOrientation(indices)
        let widths = indices.map { observations[$0].boundingRect.width }.sorted()
        let heights = indices.map { observations[$0].boundingRect.height }.sorted()
        let medianWidth = widths[widths.count / 2]
        let medianHeight = heights[heights.count / 2]

        switch orientation {
            case .vertical: return orderVertical(indices, columnBand: max(medianWidth * 0.52, 0.008))
            case .leftToRight: return orderHorizontal(indices, rowBand: max(medianHeight * 0.65, 0.010), leftToRight: true)
            case .rightToLeft: return orderHorizontal(indices, rowBand: max(medianHeight * 0.65, 0.010), leftToRight: false)
        }
    }

    private func computeClusterIndices() -> [[Int]] {
        var unvisited = Set(observations.indices)
        var clusters: [[Int]] = []

        while let seed = unvisited.first {
            var cluster: [Int] = []
            var queue = [seed]
            unvisited.remove(seed)

            while let current = queue.first {
                queue.removeFirst()
                cluster.append(current)
                for neighbor in unvisited where isContextNeighbor(current, neighbor) {
                    queue.append(neighbor)
                }
                for item in queue {
                    unvisited.remove(item)
                }
            }

            clusters.append(cluster)
        }

        return clusters
    }

    private func orderVertical(_ indices: [Int], columnBand: CGFloat) -> [Int] {
        struct Column {
            var centerX: CGFloat
            var members: [Int]
        }

        var columns: [Column] = []
        let sortedByX = indices.sorted { observations[$0].boundingRect.midX > observations[$1].boundingRect.midX }

        for idx in sortedByX {
            let x = observations[idx].boundingRect.midX
            if
                let colIndex = columns
                    .enumerated()
                    .min(by: { abs($0.element.centerX - x) < abs($1.element.centerX - x) })
                    .map(\.offset),
                abs(columns[colIndex].centerX - x) <= columnBand
            {
                columns[colIndex].members.append(idx)
                let count = CGFloat(columns[colIndex].members.count)
                columns[colIndex].centerX = (columns[colIndex].centerX * (count - 1) + x) / count
            } else {
                columns.append(Column(centerX: x, members: [idx]))
            }
        }

        columns.sort { $0.centerX > $1.centerX }

        var ordered: [Int] = []
        for column in columns {
            let members = column.members.sorted { lhs, rhs in
                let a = observations[lhs].boundingRect
                let b = observations[rhs].boundingRect
                if abs(a.midY - b.midY) > 0.004 { return a.midY < b.midY }
                return a.midX > b.midX
            }
            ordered.append(contentsOf: members)
        }
        return ordered
    }

    private func orderHorizontal(_ indices: [Int], rowBand: CGFloat, leftToRight: Bool) -> [Int] {
        struct Row {
            var centerY: CGFloat
            var members: [Int]
        }

        var rows: [Row] = []
        let sortedByY = indices.sorted { observations[$0].boundingRect.midY < observations[$1].boundingRect.midY }

        for idx in sortedByY {
            let y = observations[idx].boundingRect.midY
            if
                let rowIndex = rows
                    .enumerated()
                    .min(by: { ($0.element.centerY - y) < abs($1.element.centerY - y) })
                    .map(\.offset),
                abs(rows[rowIndex].centerY - y) <= rowBand
            {
                rows[rowIndex].members.append(idx)
                let count = CGFloat(rows[rowIndex].members.count)
                rows[rowIndex].centerY = (rows[rowIndex].centerY * (count - 1) + y) / count
            } else {
                rows.append(Row(centerY: y, members: [idx]))
            }
        }

        rows.sort { $0.centerY < $1.centerY }

        var ordered: [Int] = []
        for row in rows {
            let members = row.members.sorted { lhs, rhs in
                let a = observations[lhs].boundingRect
                let b = observations[rhs].boundingRect
                if abs(a.midX - b.midX) > 0.004 {
                    return leftToRight ? (a.midX < b.midX) : (a.midX > b.midX)
                }
                return a.midY < b.midY
            }
            ordered.append(contentsOf: members)
        }
        return ordered
    }

    private func clusterOrientation(_ indices: [Int]) -> ReadingOrientation {
        guard !indices.isEmpty else { return .leftToRight }

        var verticalScore: Float = 0
        var ltrScore: Float = 0
        var rtlScore: Float = 0

        for idx in indices {
            let obs = observations[idx]
            let weight = max(obs.confidence, 0.35)
            switch obs.direction {
                case .topToBottom:
                    verticalScore += weight
                case .leftToRight:
                    ltrScore += weight
                case .rightToLeft:
                    rtlScore += weight
                case .unknown:
                    let box = obs.boundingRect
                    if box.height > box.width * 1.1 {
                        verticalScore += weight * 0.7
                    } else {
                        ltrScore += weight * 0.7
                    }
            }
        }

        if verticalScore >= ltrScore && verticalScore >= rtlScore {
            return .vertical
        }
        if rtlScore > ltrScore {
            return .rightToLeft
        }
        return .leftToRight
    }

    private func orientation(for index: Int) -> ReadingOrientation {
        let obs = observations[index]
        switch obs.direction {
            case .topToBottom:
                return .vertical
            case .leftToRight:
                return .leftToRight
            case .rightToLeft:
                return .rightToLeft
            case .unknown:
                let box = obs.boundingRect
                return box.height > box.width * 1.1 ? .vertical : .leftToRight
        }
    }

    private func isContextNeighbor(_ lhs: Int, _ rhs: Int) -> Bool {
        let a = observations[lhs].boundingRect
        let b = observations[rhs].boundingRect
        let centerDistance = hypot(a.midX - b.midX, a.midY - b.midY)
        let sizeScale = max(max(a.width, a.height), max(b.width, b.height))
        guard centerDistance <= sizeScale * 3.5 else { return false }

        let xGap = max(0, max(b.minX - a.maxX, a.minX - b.maxX))
        let yGap = max(0, max(b.minY - a.maxY, a.minY - b.maxY))

        let xOverlap = overlapRatio(a.minX, a.maxX, b.minX, b.maxX, divisor: min(a.width, b.width))
        let yOverlap = overlapRatio(a.minY, a.maxY, b.minY, b.maxY, divisor: min(a.height, b.height))

        let lhsOrientation = orientation(for: lhs)
        let rhsOrientation = orientation(for: rhs)

        if lhsOrientation == .vertical && rhsOrientation == .vertical {
            let thicknessScale = max(min(a.width, a.height), min(b.width, b.height))
            let sameColumn = xOverlap > 0.45 && yGap < thicknessScale * 1.8
            let adjacentColumn = yOverlap > 0.50 && xGap < thicknessScale * 1
            guard sameColumn || adjacentColumn else { return false }
            let connected = centerDistance <= thicknessScale * 3
            return connected
        }

        let sameLine = yOverlap > 0.28 && xGap < max(a.width, b.width) * 1.2
        let adjacentLine = xOverlap > 0.28 && yGap < max(a.height, b.height) * 1.6
        let sameColumn = xOverlap > 0.28 && yGap < max(a.height, b.height) * 1.2
        let adjacentColumn = yOverlap > 0.28 && xGap < max(a.width, b.width) * 1.6
        guard sameLine || adjacentLine || sameColumn || adjacentColumn else { return false }

        if lhsOrientation == rhsOrientation {
            return centerDistance <= sizeScale * 3.5
        }

        return centerDistance <= sizeScale * 1.15
    }

    private func overlapRatio(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat, divisor: CGFloat) -> CGFloat {
        guard divisor > 0 else { return 0 }
        let overlap = max(0, min(a1, b1) - max(a0, b0))
        return overlap / divisor
    }
}

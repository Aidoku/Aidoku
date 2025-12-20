//
//  HeatmapData.swift
//  Aidoku
//
//  Created by Skitty on 12/20/25.
//

import Foundation

struct HeatmapData: Hashable {
    let startDate: Date
    let values: [Int]

    static func getDaysAndStartDate() -> (totalDays: Int, startDate: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let initialStartDate = calendar.date(byAdding: .day, value: -364, to: today)!

        let daysToSubtract = calendar.component(.weekday, from: initialStartDate) - 1
        let alignedStartDate = calendar.date(byAdding: .day, value: -daysToSubtract, to: initialStartDate)!

        let totalDays = 365 + daysToSubtract

        return (totalDays, alignedStartDate)
    }

    static func empty() -> HeatmapData {
        let (totalDays, startDate) = getDaysAndStartDate()
        return .init(
            startDate: startDate,
            values: Array(repeating: 0, count: totalDays)
        )
    }

    static func demo() -> HeatmapData {
        let (totalDays, startDate) = getDaysAndStartDate()
        return .init(
            startDate: startDate,
            values: (0..<totalDays).map { _ in
                Int.random(in: 0...5)
            }
        )
    }
}

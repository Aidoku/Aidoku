//
//  InsightsData.swift
//  Aidoku
//
//  Created by Skitty on 12/20/25.
//

import Foundation

struct InsightsData {
    var currentStreak: Int
    var longestStreak: Int
    var heatmapData: HeatmapData
    var chartData: [YearlyMonthData]
    let statsData: [SmallStatData]

    init(
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        heatmapData: HeatmapData = .empty(),
        chartData: [YearlyMonthData] = [],
        pagesTotal: Int = 0,
        pagesMonth: Int = 0,
        pagesYear: Int = 0,
        seriesTotal: Int = 0,
        seriesMonth: Int = 0,
        seriesYear: Int = 0,
        hoursTotal: Int = 0,
        hoursMonth: Int = 0,
        hoursYear: Int = 0
    ) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.heatmapData = heatmapData
        self.chartData = chartData
        self.statsData = [
            .init(
                total: pagesTotal,
                thisMonth: pagesMonth,
                thisYear: pagesYear,
                subtitle: NSLocalizedString("PAGE_PLURAL"),
                singularSubtitle: NSLocalizedString("PAGE_SINGULAR")
            ),
            .init(
                total: seriesTotal,
                thisMonth: seriesMonth,
                thisYear: seriesYear,
                subtitle: NSLocalizedString("SERIES_PLURAL"),
                singularSubtitle: NSLocalizedString("SERIES_SINGULAR")
            ),
            .init(
                total: hoursTotal,
                thisMonth: hoursMonth,
                thisYear: hoursYear,
                subtitle: NSLocalizedString("HOUR_PLURAL"),
                singularSubtitle: NSLocalizedString("HOUR_SINGULAR")
            )
        ]
    }

    static func get() async -> InsightsData {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let (currentStreak, longestStreak) = CoreDataManager.shared.getStreakLengths(context: context)
            let basicStats = CoreDataManager.shared.getBasicStats(context: context)
            let chartData = CoreDataManager.shared.getChapterYearlyReadingData(context: context)
            let heatmapData = CoreDataManager.shared.getReadingHeatmapData()
            return InsightsData(
                currentStreak: currentStreak,
                longestStreak: longestStreak,
                heatmapData: heatmapData,
                chartData: chartData,
                pagesTotal: basicStats.pagesTotal,
                pagesMonth: basicStats.pagesMonth,
                pagesYear: basicStats.pagesYear,
                seriesTotal: basicStats.seriesTotal,
                seriesMonth: basicStats.seriesMonth,
                seriesYear: basicStats.seriesYear,
                hoursTotal: basicStats.hoursTotal,
                hoursMonth: basicStats.hoursMonth,
                hoursYear: basicStats.hoursYear
            )
        }
    }

    static let demoData: InsightsData = .init(
        currentStreak: 2,
        longestStreak: 3,
        heatmapData: .demo(),
        chartData: [
            .init(year: 2025, data: .init(
                january: 0,
                february: 0,
                march: 0,
                april: 0,
                may: 8,
                june: 0,
                july: 0,
                august: 0,
                september: 9,
                october: 0,
                november: 10,
                december: 1
            )),
            .init(year: 2024, data: .init(
                january: 1,
                february: 0,
                march: 0,
                april: 0,
                may: 8,
                june: 0,
                july: 0,
                august: 0,
                september: 0,
                october: 2,
                november: 7,
                december: 8
            ))
        ],
        pagesTotal: 2354,
        pagesMonth: 34,
        pagesYear: 1234,
        seriesTotal: 4,
        seriesMonth: 0,
        seriesYear: 2,
        hoursTotal: 1,
        hoursMonth: 0,
        hoursYear: 1
    )
}

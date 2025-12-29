//
//  YearlyMonthChartView.swift
//  Aidoku
//
//  Created by Skitty on 12/17/25.
//

import Charts
import SwiftUI

extension Month: Identifiable {
    var id: Int { rawValue }

    var axisLabel: String {
        let locale = Locale.current
        let formatter = DateFormatter()
        formatter.locale = locale
        let monthSymbols = formatter.shortMonthSymbols ?? formatter.monthSymbols ?? []
        let label = monthSymbols[rawValue - 1]

        // use full label for cjk
        if let languageCode = locale.languageCode, ["ja", "zh", "ko"].contains(languageCode) {
            let fullMonthSymbols = formatter.monthSymbols ?? []
            return fullMonthSymbols[rawValue - 1]
        }

        // otherwise use first letter
        return String(label.prefix(1))
    }
}

@available(iOS 16.0, *)
struct YearlyMonthChartView: View {
    let data: MonthData

    private let maxY: Int

    init(data: MonthData) {
        self.data = data
        self.maxY = max(data.maxValue, 10) // at least 10
    }

    var body: some View {
        Chart {
            ForEach(Month.allCases) { month in
                let value = data.value(for: month)
                BarMark(
                    x: .value("Month", month.rawValue),
                    yStart: .value("Value", -0.15), // start slightly below the axis
                    yEnd: .value("Value", value == 0 ? 0.15 : Double(value)), // ensure at least 0.3 height
                    width: 2
                )
                .foregroundStyle(.primary)
            }
        }
        .chartXScale(domain: 0.4...12.6)
        .chartYScale(domain: 0...maxY) // ensure the negative values don't mess up the graph
        .chartXAxis {
            // show first letter for each month
            AxisMarks(values: Array(1...12)) { value in
                let locale = Locale.current
                let isCJK = ["ja", "zh", "ko"].contains(locale.languageCode ?? "")
                if
                    let intValue = value.as(Int.self),
                    let month = Month(rawValue: intValue),
                    !isCJK || (isCJK && intValue % 2 == 1) // skip every other in cjk (because labels are wider)
                {
                    let value = data.value(for: month)
                    AxisValueLabel(anchor: .top) {
                        Text(month.axisLabel)
                            .font(.caption2.weight(.semibold))
                            .offset(y: 2)
                            .fixedSize()
                    }
                    .foregroundStyle(value == 0 ? .secondary : .primary)
                }
            }
        }
        .chartYAxis {
            // ideally show three marks: zero, mid, max
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text(intValue, format: .number)
                            .font(.system(size: 9, weight: .medium))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .foregroundStyle(.primary) // by default it uses accent color
    }
}

@available(iOS 16.0, *)
#Preview {
    YearlyMonthChartView(data: .init(
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
    ))
    .frame(height: 104)
}

//
//  HeatmapView.swift
//  Aidoku
//
//  Created by Skitty on 12/17/25.
//

import SwiftUI

struct HeatmapView: View {
    let data: HeatmapData

    private let weekCount: Int
    private let colorForValue: (Int) -> Color
    private let calendar = Calendar.current
    private let monthHeaders: [(index: Int, label: String)]

    private let cellSize: CGFloat = 16
    private let cellSpacing: CGFloat = 2
    private let headerHeight: CGFloat = 16
    private let headerSpacing: CGFloat = 4

    init(data: HeatmapData, themeColor: Color? = nil) {
        self.data = data
        self.weekCount = (data.values.count + 6) / 7 // round result up instead of truncating

        // do "quantile bucketing" to determine heatmap colors
        let themeColor = themeColor ?? .accentColor
        let noColor = Color(uiColor: .init(dynamicProvider: { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                .tertiarySystemGroupedBackground
            } else {
                .systemGray6
            }
        }))
        let colors = [
            themeColor.opacity(0.3),
            themeColor.opacity(0.4),
            themeColor.opacity(0.6),
            themeColor.opacity(0.8),
            themeColor
        ]
        let bucketCount = colors.count
        let sortedValues = data.values.sorted().filter { $0 > 0 }
        if !sortedValues.isEmpty {
            let thresholds = (0..<bucketCount).map { i in
                let q = Int(floor(Float(i) / Float(bucketCount) * Float(sortedValues.count)))
                return sortedValues[q]
            }
            self.colorForValue = { value in
                if value == 0 {
                    return noColor
                }
                let bucketIndex = thresholds.firstIndex { value <= $0 } ?? bucketCount - 1
                return colors[bucketIndex]
            }
        } else {
            self.colorForValue = { _ in noColor }
        }

        var result: [(Int, String)] = []
        var lastMonth: Int?
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        for i in 0..<weekCount {
            let offset = i * 7
            let firstDay = calendar.date(byAdding: .day, value: offset, to: data.startDate)!
            let month = calendar.component(.month, from: firstDay)
            if month != lastMonth {
                // if two month headers are right next to each other, remove the first one
                if !result.isEmpty && i == result[result.count - 1].0 + 1 {
                    result.removeLast()
                }
                result.append((i, formatter.string(from: firstDay)))
                lastMonth = month
            }
        }
        self.monthHeaders = result
    }

    var body: some View {
        ScrollViewReader { proxy in
            let height = 7 * (cellSize + cellSpacing) + headerHeight + headerSpacing * 2
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    // month headers
                    ForEach(monthHeaders, id: \.index) { header in
                        Text(header.label)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: headerHeight, alignment: .leading)
                            .offset(x: CGFloat(header.index) * (cellSize + cellSpacing))
                    }

                    // heatmap cells
                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(0..<weekCount, id: \.self) { weekIndex in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { dayIndex in
                                    let offset = weekIndex * 7 + dayIndex
                                    if data.values.indices.contains(offset) {
                                        let value = data.values[offset]
                                        let date = calendar.date(byAdding: .day, value: offset, to: data.startDate)!
                                        Rectangle()
                                            .fill(colorForValue(value))
                                            .frame(width: cellSize, height: cellSize)
                                            .cornerRadius(3)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 3)
                                                    .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                                            )
                                            .accessibilityLabel(Text("\(date): \(value)"))
                                    }
                                }
                            }
                            .id(weekIndex == weekCount - 1 ? "lastWeek" : nil)
                        }
                    }
                    .padding(.top, headerHeight + headerSpacing)
                }
                .frame(
                    width: CGFloat(weekCount) * (cellSize + cellSpacing),
                    height: height
                )
            }
            .frame(height: height)
            .onAppear {
                proxy.scrollTo("lastWeek")
            }
            .onChange(of: data) { _ in
                proxy.scrollTo("lastWeek", anchor: .trailing)
            }
        }
        .centerScrollAnchorPlease()
        .scrollClipDisabledPlease()
    }
}

#Preview {
    HeatmapView(data: .demo(), themeColor: .green)
        .padding()
}

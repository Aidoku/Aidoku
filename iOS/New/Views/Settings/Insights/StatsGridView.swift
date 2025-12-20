//
//  StatsGridView.swift
//  Aidoku
//
//  Created by Skitty on 12/18/25.
//

import SwiftUI

struct StatsGridView: View {
    static let cornerRadius: CGFloat = 12
    static let spacing: CGFloat = 8

    let chartLabel: String
    var chartSingularLabel: String?
    let chartData: [YearlyMonthData]
    let items: [SmallStatData]

    @Binding var height: CGFloat

    @State private var expandedIndex: Int?
    @State private var selectedChartYear: Int? // nil is all-time

    @Namespace private var animation

    // when block sizes are greater than this, halve the height to make them rectangles (e.g. on ipad)
    static let largestSquareSize: CGFloat = 260

    static let chartHeight: CGFloat = 109
    static let chartExpansionHeight: CGFloat = 50

    private var chartCanExpand: Bool {
        chartData.count > 1
    }
    private var chartIsExpanded: Bool {
        (usingHorizontalLayout || expandedIndex == items.count) && chartCanExpand
    }
    private var selectedChartTotal: Int {
        selectedChartData.total
    }
    private var selectedChartData: MonthData {
        if let selectedChartYear {
            return chartData.first(where: { $0.year == selectedChartYear })!.data
        } else {
            // combine all chart data
            var total: MonthData = .init()
            for yearlyData in chartData {
                total.january += yearlyData.data.january
                total.february += yearlyData.data.february
                total.march += yearlyData.data.march
                total.april += yearlyData.data.april
                total.may += yearlyData.data.may
                total.june += yearlyData.data.june
                total.july += yearlyData.data.july
                total.august += yearlyData.data.august
                total.september += yearlyData.data.september
                total.october += yearlyData.data.october
                total.november += yearlyData.data.november
                total.december += yearlyData.data.december
            }
            return total
        }
    }

    private var usingHorizontalLayout: Bool {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let orientation =
            if #available(iOS 16.0, *) {
                scene?.effectiveGeometry.interfaceOrientation
            } else {
                scene?.interfaceOrientation
            }
        return orientation == .landscapeLeft || orientation == .landscapeRight
    }

    var body: some View {
        if usingHorizontalLayout {
            HStack(spacing: Self.spacing) {
                mainContent
            }
            .animation(.easeInOut, value: expandedIndex)
        } else {
            VStack(spacing: Self.spacing) {
                mainContent
            }
            .animation(.easeInOut, value: expandedIndex)
        }
    }

    @ViewBuilder
    var mainContent: some View {
        // monthly chart
        if #available(iOS 16.0, *) {
            let defaultChartHeight = Self.chartHeight + (chartIsExpanded ? Self.chartExpansionHeight : 0)
            GeometryReader { geo in
                let totalSpacing = 2 * Self.spacing
                let normalSquare = (geo.size.width - totalSpacing) / 3

                let totalHeight = usingHorizontalLayout ? normalSquare : defaultChartHeight

                InsightPlatterView {
                    VStack(spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: -8) {
                                let total = selectedChartTotal
                                Text(total, format: .number.notation(.compactName))
                                    .contentTransition(.numericText())
                                    .font(.system(size: 64).weight(.bold))
                                    .minimumScaleFactor(0.5)
                                Text(total == 1 ? chartSingularLabel ?? chartLabel : chartLabel)
                                    .font(.system(size: 17).weight(.semibold))
                                    .padding(.bottom, 5)
                            }
                            .frame(width: 120, alignment: .leading)

                            YearlyMonthChartView(data: selectedChartData)
                                .padding(.vertical, 2)
                        }
                        .padding(12)
                        .frame(
                            height: usingHorizontalLayout
                                ? normalSquare - (chartIsExpanded ? Self.chartExpansionHeight : 0)
                                : Self.chartHeight
                        )

                        if chartIsExpanded {
                            ScrollView(.horizontal) {
                                HStack(spacing: 2) {
                                    YearSelectorView(selectedYear: $selectedChartYear)
                                    ForEach(chartData, id: \.year) { yearlyData in
                                        YearSelectorView(year: yearlyData.year, selectedYear: $selectedChartYear)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .scrollClipDisabledPlease()
                        }
                    }
                    .frame(
                        height: totalHeight,
                        alignment: .top
                    )
                    .frame(maxWidth: .infinity)
                }
                .onTapGesture {
                    if expandedIndex == items.count {
                        expandedIndex = nil
                        if chartCanExpand {
                            height -= Self.chartExpansionHeight
                        }
                    } else {
                        expandedIndex = items.count
                        if chartCanExpand {
                            height += Self.chartExpansionHeight
                        }
                    }
                }
            }
            .frame(height: usingHorizontalLayout ? nil : defaultChartHeight)
        }

        // small stats blocks
        GeometryReader { geo in
            let totalSpacing = 2 * Self.spacing
            let normalSquare = (geo.size.width - totalSpacing) / 3
            let expandedSquare = normalSquare * 2 + Self.spacing

            let isTooLargeForSquare = normalSquare > Self.largestSquareSize

            ZStack(alignment: .topLeading) {
                ForEach(0..<3) { i in
                    squareView(
                        index: i,
                        size: size(for: i, normal: normalSquare, expanded: expandedSquare),
                        expanded: expandedIndex == i
                    )
                    .matchedGeometryEffect(id: i, in: animation)
                    .position(position(for: i, normal: normalSquare, expanded: expandedSquare))
                    .zIndex(expandedIndex == i ? 1 : 0)
                    .onTapGesture {
                        expandedIndex = expandedIndex == i ? nil : i
                    }
                }
            }
            .frame(
                width: geo.size.width,
                height: {
                    if isTooLargeForSquare {
                        normalSquare / 2
                    } else {
                        expandedIndex == nil || expandedIndex == items.count ? normalSquare : expandedSquare
                    }
                }()
            )
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        height = geometry.frame(in: .local).size.height
                            + Self.chartHeight
                            + Self.spacing
                            + (chartIsExpanded ? Self.chartExpansionHeight : 0)
                    }
                    .onChange(of: geometry.size) { _ in
                        height = geometry.frame(in: .local).size.height
                            + Self.chartHeight
                            + Self.spacing
                            + (chartIsExpanded ? Self.chartExpansionHeight : 0)
                    }
            })
        }
    }

    func size(for i: Int, normal: CGFloat, expanded: CGFloat) -> CGSize {
        let isTooLargeForSquare = normal > Self.largestSquareSize
        if let expandedIndex {
            if i == expandedIndex {
                return CGSize(width: expanded, height: isTooLargeForSquare ? expanded / 2 : expanded)
            } else {
                return CGSize(width: normal, height: isTooLargeForSquare ? normal / 2 : normal)
            }
        } else {
            return CGSize(width: normal, height: isTooLargeForSquare ? normal / 2 : normal)
        }
    }

    func position(for i: Int, normal: CGFloat, expanded: CGFloat) -> CGPoint {
        let isTooLargeForSquare = normal > Self.largestSquareSize
        let normalHeight = isTooLargeForSquare ? normal / 2 : normal
        let expandedHeight = isTooLargeForSquare ? expanded / 2 : expanded

        lazy var expandedTopLeft = CGPoint(x: expanded / 2, y: expandedHeight / 2)
        lazy var expandedTopRight = CGPoint(x: normal + Self.spacing + expanded / 2, y: expandedHeight / 2)
        lazy var smallTopLeft = CGPoint(x: normal / 2, y: normalHeight / 2)
        lazy var smallBottomLeft = CGPoint(x: normal / 2, y: normalHeight + Self.spacing + normalHeight / 2)
        lazy var smallTopRight = CGPoint(x: expanded + Self.spacing + normal / 2, y: normalHeight / 2)
        lazy var smallBottomRight = CGPoint(
            x: expanded + Self.spacing + normal / 2,
            y: normalHeight + Self.spacing + normalHeight / 2
        )

        if let expandedIndex, expandedIndex < items.count {
            switch expandedIndex {
                case 0:
                    if i == expandedIndex {
                        return expandedTopLeft
                    } else {
                        return i == 1 ? smallTopRight : smallBottomRight
                    }
                case 1:
                    if i == expandedIndex {
                        return expandedTopRight
                    } else {
                        return i == 0 ? smallTopLeft : smallBottomLeft
                    }
                case 2:
                    if i == expandedIndex {
                        return expandedTopRight
                    } else {
                        return i == 0 ? smallTopLeft : smallBottomLeft
                    }
                default: fatalError("invalid index")
            }
        } else {
            let x = CGFloat(i) * (normal + Self.spacing) + normal / 2
            let y = normalHeight / 2
            return CGPoint(x: x, y: y)
        }
    }

    @ViewBuilder
    func squareView(index: Int, size: CGSize, expanded: Bool) -> some View {
        InsightPlatterView {
            ZStack {
                VStack {
                    Text(items[index].total, format: .number.notation(.compactName))
                        .font(.system(size: expanded ? 52 : 36).weight(.bold))
                    Text(items[index].total == 1 ? items[index].singularSubtitle ?? items[index].subtitle : items[index].subtitle)
                        .font(.system(size: expanded ? 18 : 14).weight(expanded ? .medium : .regular))
                }
                if expanded {
                    VStack {
                        Spacer()
                        HStack {
                            VStack {
                                Text(items[index].thisMonth, format: .number.notation(.compactName))
                                    .font(.title.weight(.bold))
                                Text(NSLocalizedString("THIS_MONTH"))
                                    .font(.system(size: 14))
                            }
                            Spacer()
                            VStack {
                                Text(items[index].thisYear, format: .number.notation(.compactName))
                                    .font(.title.weight(.bold))
                                Text(NSLocalizedString("THIS_YEAR"))
                                    .font(.system(size: 14))
                            }
                        }
                        .padding()
                        .padding(.horizontal, 4)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.default.delay(0.2)),
                            removal: .opacity
                        ))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    struct YearSelectorView: View {
        var year: Int?
        @Binding var selectedYear: Int?

        private var title: String {
            if let year {
                String(format: "%i", year)
            } else {
                NSLocalizedString("ALL_TIME")
            }
        }

        private var selected: Bool {
            selectedYear == year
        }

        var body: some View {
            VStack {
                Button(title) {
                    withAnimation {
                        selectedYear = year
                    }
                }
                .font(.callout)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 100).fill(selected ? Color(uiColor: .secondarySystemFill) : .clear))
            .foregroundStyle(selected ? .primary : .secondary)
        }
    }
}

//
//  InsightsView.swift
//  Aidoku
//
//  Created by Skitty on 12/16/25.
//

import SwiftUI

struct InsightsView: View {
    @State private var data: InsightsData = .init()
    @State private var statsGridHeight: CGFloat = .zero
    @State private var shouldAnimateGridHeightChange = false

    init(data: InsightsData? = nil) {
        _data = State(initialValue: data ?? .init())
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("STREAKS"))
                            .font(.system(size: 15).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                InsightPlatterView {
                                    Group {
                                        if data.currentStreak > 1 {
                                            VStack(spacing: 0) {
                                                Text(NSLocalizedString("CURRENT_STREAK"))
                                                    .font(.system(size: 14))
                                                VStack(spacing: -5) {
                                                    Text(data.currentStreak, format: .number.notation(.compactName))
                                                        .font(.system(size: 38).weight(.bold))
                                                    Text(NSLocalizedString("DAYS"))
                                                        .font(.body.weight(.semibold))
                                                        .multilineTextAlignment(.center)
                                                }
                                            }
                                        } else {
                                            VStack(spacing: 4) {
                                                Text(NSLocalizedString("NO_CURRENT_STREAK"))
                                                    .font(.headline)
                                                Text(NSLocalizedString("NO_CURRENT_STREAK_TEXT"))
                                                    .font(.subheadline)
                                                    .multilineTextAlignment(.center)
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .frame(height: 110)
                                    .frame(maxWidth: .infinity)
                                }

                                if data.longestStreak > data.currentStreak && data.longestStreak > 1 {
                                    InsightPlatterView {
                                        VStack(spacing: 0) {
                                            Text(NSLocalizedString("LONGEST_STREAK"))
                                                .font(.system(size: 14))
                                            VStack(spacing: -5) {
                                                Text(data.longestStreak, format: .number.notation(.compactName))
                                                    .font(.system(size: 38).weight(.bold))
                                                Text(NSLocalizedString("DAYS"))
                                                    .font(.body.weight(.semibold))
                                                    .multilineTextAlignment(.center)
                                            }
                                        }
                                        .padding(12)
                                        .frame(height: 110)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }

                            InsightPlatterView {
                                HStack(spacing: 0) {
                                    LinearGradient(
                                        gradient: Gradient(
                                            colors: [
                                                Color(UIColor.secondarySystemGroupedBackground),
                                                Color(UIColor.secondarySystemGroupedBackground).opacity(0)
                                            ]
                                        ),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .frame(width: 12)
                                    .zIndex(1)

                                    HeatmapView(data: data.heatmapData)
                                        .padding(.vertical, 12)
                                        .zIndex(0)

                                    LinearGradient(
                                        gradient: Gradient(
                                            colors: [
                                                Color(UIColor.secondarySystemGroupedBackground).opacity(0),
                                                Color(UIColor.secondarySystemGroupedBackground)
                                            ]
                                        ),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .flipsForRightToLeftLayoutDirection(true)
                                    .frame(width: 12)
                                    .zIndex(1)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(NSLocalizedString("STATS"))
                            .font(.system(size: 15).weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        StatsGridView(
                            chartLabel: NSLocalizedString("CHAPTER_PLURAL"),
                            chartSingularLabel: NSLocalizedString("CHAPTER_SINGULAR"),
                            chartData: data.chartData,
                            items: data.statsData,
                            height: $statsGridHeight
                        )
                        .frame(height: statsGridHeight)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .animation(shouldAnimateGridHeightChange ? .default : nil, value: statsGridHeight)
            .onChangeWrapper(of: statsGridHeight) { oldValue, _ in
                // prevent animation on initial height set
                if oldValue != 0 {
                    shouldAnimateGridHeightChange = true
                }
            }
        }
        .navigationTitle(NSLocalizedString("INSIGHTS"))
        .task {
            guard data.currentStreak == 0 else { return }
            data = await .get()
        }
    }
}

#Preview {
    PlatformNavigationStack {
        InsightsView(data: .demoData)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {} label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
    }
}

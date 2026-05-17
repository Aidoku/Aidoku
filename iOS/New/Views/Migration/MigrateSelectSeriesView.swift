//
//  MigrateSelectSeriesView.swift
//  Aidoku
//
//  Created by skitty on 5/9/26.
//

import AidokuRunner
import SwiftUI

struct MigrateSelectSeriesView: View {
    let sourceName: String
    let series: [AidokuRunner.Manga]
    let source: AidokuRunner.Source?

    @State private var selectedKeys: Set<String>
    @State private var editMode = EditMode.active

    @EnvironmentObject private var path: NavigationCoordinator

    init(sourceName: String, series: [AidokuRunner.Manga], source: AidokuRunner.Source?) {
        self.sourceName = sourceName
        self.series = series
        self.source = source
        self._selectedKeys = State(initialValue: Set(series.map { $0.key }))
    }

    var body: some View {
        let list = List(selection: $selectedKeys) {
            let title = String(format: NSLocalizedString("SELECTED_%i_OF_%i"), selectedKeys.count, series.count)
            Section(title) {
                ForEach(series.indices, id: \.self) { index in
                    let item = series[index]
                    SeriesCell(source: source, item: item)
                        .tag(item.key)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle(sourceName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let navigationController = path.rootViewController as? UINavigationController else { return }
            navigationController.isToolbarHidden = false
            navigationController.toolbar.alpha = 1
        }

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    toolbarContentiOS18
                }
        }
    }

    @ToolbarContentBuilder
    var commonToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            let selectedSeries = series.filter { selectedKeys.contains($0.key) }
            Button(NSLocalizedString("CONTINUE")) {
                path.push(MigrateSelectDestinationView(
                    selectedSeries: selectedSeries,
                    selectedSources: source.flatMap { [$0.toInfo()] } ?? []
                ))
            }
            .disabled(selectedKeys.isEmpty)
        }
    }

    @ViewBuilder
    var selectAllButton: some View {
        let allSelected = selectedKeys.count == series.count
        if allSelected {
            Button(NSLocalizedString("DESELECT_ALL")) {
                selectedKeys = Set()
            }
        } else {
            Button(NSLocalizedString("SELECT_ALL")) {
                selectedKeys = Set(series.map { $0.key })
            }
        }
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        commonToolbarContent

        ToolbarSpacer(.flexible, placement: .bottomBar)

        ToolbarItem(placement: .bottomBar) {
            selectAllButton
        }
    }

    @ToolbarContentBuilder
    var toolbarContentiOS18: some ToolbarContent {
        commonToolbarContent

        ToolbarItem(placement: .bottomBar) {
            HStack {
                Spacer()
                selectAllButton
            }
        }
    }
}

extension MigrateSelectSeriesView {
    struct SeriesCell: View {
        let source: AidokuRunner.Source?
        let item: AidokuRunner.Manga

        private let coverWidth: CGFloat = 42
        private let coverHeight: CGFloat = 42

        var body: some View {
            HStack(spacing: 12) {
                MangaCoverView(
                    source: source,
                    coverImage: item.cover ?? "",
                    width: coverWidth,
                    height: coverHeight
                )

                Text(item.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
        }
    }
}

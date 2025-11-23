//
//  TrackerListView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/19/22.
//

import AidokuRunner
import SwiftUI

struct TrackerListView: View {
    let manga: AidokuRunner.Manga

    @State private var refresh = false
    @State private var availableTrackers: [Tracker] = []
    @State private var trackerInfo: [String: TrackerInfo] = [:]

    let refreshPublisher = NotificationCenter.default.publisher(for: .updateTrackers)

    var body: some View {
        VStack {
            if availableTrackers.isEmpty {
                VStack {
                    ProgressView().progressViewStyle(.circular)
                }
                .frame(height: 60)
            } else {
                ForEach(availableTrackers, id: \.id) { tracker in
                    if
                        let item = CoreDataManager.shared.getTrack(
                            trackerId: tracker.id,
                            sourceId: manga.sourceKey,
                            mangaId: manga.key
                        )?.toItem(),
                        let info = trackerInfo[tracker.id]
                    {
                        TrackerView(tracker: tracker, item: item, info: info, refresh: $refresh)
                            .transition(.opacity)
                    } else {
                        TrackerAddView(tracker: tracker, manga: manga, refresh: $refresh)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding([.bottom])
        .onChange(of: refresh) { _ in } // in order to trigger a refresh
        .onReceive(refreshPublisher) { _ in
            withAnimation {
                refresh.toggle()
            }
        }
        .task {
            var trackers: [Tracker] = []
            for tracker in TrackerManager.trackers {
                let canRegister = try? await tracker.canRegister(sourceKey: manga.sourceKey, mangaKey: manga.key)
                if canRegister == true {
                    let info = try? await tracker.getTrackerInfo()
                    guard let info else { continue }
                    trackers.append(tracker)
                    trackerInfo[tracker.id] = info
                }
            }
            withAnimation {
                availableTrackers = trackers
            }
        }
    }
}

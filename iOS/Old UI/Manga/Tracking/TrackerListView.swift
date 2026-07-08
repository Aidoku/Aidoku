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
    @State private var trackItems: [TrackItem] = []
    @State private var trackerInfo: [String: TrackerInfo] = [:]

    private let refreshPublisher = NotificationCenter.default.publisher(for: .updateTrackers)

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
                        let item = trackItems.first(where: { $0.trackerId == tracker.id }),
                        let info = trackerInfo[tracker.id]
                    {
                        TrackerView(
                            tracker: tracker,
                            item: item,
                            info: info,
                            manga: manga,
                            refresh: $refresh
                        )
                        .transition(.opacity)
                    } else {
                        TrackerAddView(tracker: tracker, manga: manga, refresh: $refresh)
                            .transition(.opacity)
                    }
                }

                let unavailableItems = trackItems.filter { item in
                    !availableTrackers.contains(where: { $0.id == item.trackerId })
                }
                ForEach(unavailableItems, id: \.trackerId) { item in
                    if let tracker = TrackerManager.getTracker(id: item.trackerId) {
                        TrackerUnavailableItemView(tracker: tracker, item: item)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding([.bottom])
        .onChange(of: refresh) { _ in } // in order to trigger a refresh
        .onReceive(refreshPublisher) { _ in
            withAnimation {
                loadTrackItems()
                refresh.toggle()
            }
        }
        .task {
            var trackers: [Tracker] = []
            for tracker in TrackerManager.trackers {
                let canRegister = tracker.canRegister(sourceKey: manga.sourceKey, mangaKey: manga.key)
                if canRegister {
                    let info = try? await tracker.getTrackerInfo()
                    guard let info else { continue }
                    trackers.append(tracker)
                    trackerInfo[tracker.id] = info
                }
            }
            loadTrackItems()
            withAnimation {
                availableTrackers = trackers
            }
        }
    }

    func loadTrackItems() {
        trackItems = CoreDataManager.shared.getTracks(sourceId: manga.sourceKey, mangaId: manga.key).map { $0.toItem() }
    }
}

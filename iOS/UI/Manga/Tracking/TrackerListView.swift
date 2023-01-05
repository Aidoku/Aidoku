//
//  TrackerListView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/19/22.
//

import SwiftUI

struct TrackerListView: View {

    let manga: Manga

    @State var refresh = false
    let refreshPublisher = NotificationCenter.default.publisher(for: Notification.Name("updateTrackers"))

    var body: some View {
        VStack {
            ForEach(TrackerManager.shared.trackers, id: \.id) { tracker in
                if tracker.isLoggedIn {
                    if let item = CoreDataManager.shared.getTrack(
                        trackerId: tracker.id,
                        sourceId: manga.sourceId,
                        mangaId: manga.id
                    )?.toItem() {
                        TrackerView(tracker: tracker, item: item, refresh: $refresh)
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
    }
}

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

    var body: some View {
        VStack {
            ForEach(TrackerManager.shared.trackers, id: \.id) { tracker in
                if tracker.isLoggedIn {
                    if let item = DataManager.shared.getTrackItem(trackerId: tracker.id, manga: manga) {
                        TrackerView(tracker: tracker, item: item, refresh: $refresh)
                            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .bottom)))
                    } else {
                        TrackerAddView(tracker: tracker, manga: manga, refresh: $refresh)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding([.bottom])
        .onChange(of: refresh) { _ in } // in order to trigger a refresh
    }
}

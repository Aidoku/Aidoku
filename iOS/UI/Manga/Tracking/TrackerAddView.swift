//
//  TrackerAddView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/20/22.
//

import SwiftUI

struct TrackerAddView: View {

    let tracker: Tracker
    let manga: Manga
    @Binding var refresh: Bool

    @State var isLoading = false

    var body: some View {
        HStack {
            ZStack {
                HStack {
                Image(uiImage: tracker.icon ?? UIImage(named: "MangaPlaceholder")!)
                    .resizable()
                    .frame(width: 44, height: 44, alignment: .leading)
                    .cornerRadius(10)
                    Spacer()
                }
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Button(NSLocalizedString("START_TRACKING", comment: "")) {
                        isLoading = true
                        Task {
                            let results = await tracker.search(for: manga)
                            if let result = results.first {
                                await tracker.register(trackId: result.id)
                                DataManager.shared.addTrackItem(
                                    item: TrackItem(
                                        id: result.id,
                                        trackerId: tracker.id,
                                        sourceId: manga.sourceId,
                                        mangaId: manga.id,
                                        title: result.title
                                    )
                                )
                                withAnimation {
                                    refresh.toggle()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding([.top, .horizontal])
    }
}

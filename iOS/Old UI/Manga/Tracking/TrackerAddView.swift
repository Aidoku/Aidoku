//
//  TrackerAddView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/20/22.
//

import AidokuRunner
import SwiftUI

struct TrackerAddView: View {
    let tracker: Tracker
    let manga: AidokuRunner.Manga
    @Binding var refresh: Bool

    @State private var isLoading = false
    @State private var showSearchView = false

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
                        .progressViewStyle(.circular)
                } else {
                    Button(NSLocalizedString("START_TRACKING")) {
                        if tracker is EnhancedTracker {
                            isLoading = true
                            Task {
                                let items = try? await tracker.search(for: manga, includeNsfw: true)
                                guard let item = items?.first else {
                                    LogManager.logger.error("Unable to find track item from tracker \(tracker.id)")
                                    return
                                }
                                await TrackerManager.shared.register(tracker: tracker, manga: manga, item: item)
                            }
                        } else {
                            showSearchView = true
                        }
                    }
                }
            }
        }
        .padding([.top, .horizontal])
        .sheet(isPresented: $showSearchView) {
            TrackerSearchView(tracker: tracker, manga: manga)
        }
    }
}

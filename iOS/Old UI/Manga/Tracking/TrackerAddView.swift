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
                        showSearchView = true
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

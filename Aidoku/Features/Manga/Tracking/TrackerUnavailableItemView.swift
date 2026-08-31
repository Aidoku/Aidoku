//
//  TrackerUnavailableItemView.swift
//  Aidoku
//
//  Created by Skitty on 2/23/26.
//

import SwiftUI

struct TrackerUnavailableItemView: View {
    let tracker: Tracker
    let item: TrackItem

    @State private var showRemoveAlert = false

    var body: some View {
        VStack {
            Button {
                showRemoveAlert = true
            } label: {
                HStack {
                    Image(uiImage: tracker.icon ?? UIImage(named: "MangaPlaceholder")!)
                        .resizable()
                        .frame(width: 44, height: 44, alignment: .leading)
                        .cornerRadius(10)
                        .padding(.trailing, 2)
                    Spacer()
                    Text(item.title ?? "")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding([.top, .horizontal])
        .alert(NSLocalizedString("UNAVAILABLE_TRACKER_ITEM"), isPresented: $showRemoveAlert) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                Task {
                    await TrackerManager.shared.removeTrackItem(item: item)
                }
            }
        } message: {
            Text(NSLocalizedString("UNAVAILABLE_TRACKER_ITEM_INFO"))
        }
    }
}

//
//  TrackerView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/26/22.
//

import SwiftUI

struct TrackerView: View {

    let tracker: Tracker
    let item: TrackItem
    @Binding var refresh: Bool

    @State var state: TrackState?

    @State var score: Float?
    @State var scoreOption: Int?
    @State var statusOption: Int?
    @State var lastReadChapter: Float?
    @State var lastReadVolume: Float?
    @State var startReadDate: Date?
    @State var finishReadDate: Date?

    @State var stateUpdated = false

    var body: some View {
        VStack {
            HStack {
                Image(uiImage: tracker.icon ?? UIImage(named: "MangaPlaceholder")!)
                    .resizable()
                    .frame(width: 44, height: 44, alignment: .leading)
                    .cornerRadius(10)
                Text(item.title ?? "")
                Spacer()
                Menu {
                    Button {
                        DataManager.shared.removeTrackObject(id: item.id, trackerId: item.trackerId)
                        stateUpdated = false
                        withAnimation {
                            refresh.toggle()
                        }
                    } label: {
                        Text(NSLocalizedString("STOP_TRACKING", comment: ""))
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .padding([.vertical, .leading]) // increase hitbox
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104))], spacing: 12) {
                TrackerSettingOptionView(
                    NSLocalizedString("STATUS", comment: ""),
                    type: .menu,
                    options: tracker.supportedStatuses.map { $0.toString() },
                    selectedOption: $statusOption
                )
                TrackerSettingOptionView(NSLocalizedString("CHAPTERS", comment: ""), type: .counter, count: $lastReadChapter)
                TrackerSettingOptionView(NSLocalizedString("VOLUMES", comment: ""), type: .counter, count: $lastReadVolume)
                TrackerSettingOptionView(NSLocalizedString("STARTED", comment: ""), type: .date, date: $startReadDate)
                TrackerSettingOptionView(NSLocalizedString("FINISHED", comment: ""), type: .date, date: $finishReadDate)

                switch tracker.scoreType {
                case .tenPoint:
                    TrackerSettingOptionView(NSLocalizedString("SCORE", comment: ""), count: $score, total: Binding.constant(10))
                case .hundredPoint:
                    TrackerSettingOptionView(NSLocalizedString("SCORE", comment: ""), count: $score, total: Binding.constant(100))
                case .tenPointDecimal:
                    TrackerSettingOptionView(NSLocalizedString("SCORE", comment: ""), count: $score, total: Binding.constant(10), numberType: .float)
                case .optionList:
                    TrackerSettingOptionView(
                        NSLocalizedString("SCORE", comment: ""),
                        type: .menu,
                        options: tracker.scoreOptions.map { $0.0 },
                        selectedOption: $scoreOption
                    )
                }
            }
        }
        .padding([.top, .horizontal])
        // handle state updates
        .onChange(of: score) { newValue in
            let new = newValue != nil ? tracker.scoreType == .tenPointDecimal ? Int(newValue! * 100) : Int(newValue!) : nil
            guard state?.score != new else { return }
            state?.score = new
            stateUpdated = true
        }
        .onChange(of: scoreOption) { newValue in
            let new = tracker.scoreOptions.enumerated().first { $0.offset == newValue }?.element.1
            guard state?.score != new else { return }
            state?.score = new
            stateUpdated = true
        }
        .onChange(of: statusOption) { newValue in
            let new = tracker.supportedStatuses.count > newValue ?? 100 ? tracker.supportedStatuses[newValue!] : nil
            guard state?.status != new else { return }
            state?.status = new
            stateUpdated = true
        }
        .onChange(of: lastReadChapter) { newValue in
            guard state?.lastReadChapter != newValue else { return }
            state?.lastReadChapter = newValue
            stateUpdated = true
        }
        .onChange(of: lastReadVolume) { newValue in
            let new = newValue != nil ? Int(ceil(newValue!)) : nil
            guard state?.lastReadVolume != new else { return }
            state?.lastReadVolume = new
            stateUpdated = true
        }
        .onChange(of: startReadDate) { newValue in
            guard state?.startReadDate != newValue else { return }
            state?.startReadDate = newValue
            stateUpdated = true
        }
        .onChange(of: finishReadDate) { newValue in
            guard state?.finishReadDate != newValue else { return }
            state?.finishReadDate = newValue
            stateUpdated = true
        }
        // fetch latest tracker state
        .onAppear {
            Task {
                state = await tracker.getState(trackId: item.id)
                guard let state = state else { return }

                withAnimation {
                    score = state.score != nil ? tracker.scoreType == .tenPointDecimal ? Float(state.score!) / 100 : Float(state.score!) : nil
                    if tracker.scoreType == .optionList {
                        scoreOption = tracker.scoreOptions.enumerated().first { $0.element.1 == state.score }?.offset
                    }
                    statusOption = tracker.supportedStatuses.enumerated().first { $0.1.rawValue == state.status?.rawValue }?.0 ?? 0
                    lastReadChapter = state.lastReadChapter != nil ? Float(state.lastReadChapter!) : nil
                    lastReadVolume = state.lastReadVolume != nil ? Float(state.lastReadVolume!) : nil
                    startReadDate = state.startReadDate
                    finishReadDate = state.finishReadDate
                }
            }
        }
        // send tracker updated state
        .onDisappear {
            if stateUpdated, let state = state {
                Task {
                    await tracker.update(trackId: item.id, state: state)
                }
            }
        }
    }
}
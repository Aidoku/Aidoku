//
//  TrackerView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/26/22.
//

import SwiftUI
import SafariServices

struct TrackerView: View {

    let tracker: Tracker
    let item: TrackItem
    @Binding var refresh: Bool

    @State var state: TrackState?
    @State var update = TrackUpdate()

    @State var score: Float?
    @State var scoreOption: Int?
    @State var statusOption: Int?
    @State var lastReadChapter: Float?
    @State var lastReadVolume: Float?
    @State var startReadDate: Date?
    @State var finishReadDate: Date?

    @State var stateUpdated = false

    @State var safariUrl: URL?
    @State var showSafari = false

    var body: some View {
        VStack {
            HStack {
                Image(uiImage: tracker.icon ?? UIImage(named: "MangaPlaceholder")!)
                    .resizable()
                    .frame(width: 44, height: 44, alignment: .leading)
                    .cornerRadius(10)
                    .padding(.trailing, 2)
                Text(item.title ?? "")
                    .lineLimit(1)
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
                    Button {
                        Task {
                            safariUrl = await tracker.getUrl(trackId: item.id)
                            guard safariUrl != nil else { return }
                            showSafari = true
                        }
                    } label: {
                        Text(NSLocalizedString("VIEW_ON_WEBSITE", comment: ""))
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
                TrackerSettingOptionView(
                    NSLocalizedString("CHAPTERS", comment: ""),
                    type: .counter,
                    count: $lastReadChapter,
                    total: Binding.constant(state?.totalChapters != nil ? Float(state!.totalChapters!) : nil)
                )
                TrackerSettingOptionView(
                    NSLocalizedString("VOLUMES", comment: ""),
                    type: .counter,
                    count: $lastReadVolume,
                    total: Binding.constant(state?.totalVolumes != nil ? Float(state!.totalVolumes!) : nil)
                )
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
            let new = newValue != nil ? tracker.scoreType == .tenPointDecimal ? Int(newValue! * 10) : Int(newValue!) : nil
            guard state?.score != new else { return }
            state?.score = new
            update.score = new
            stateUpdated = true
        }
        .onChange(of: scoreOption) { newValue in
            let new = tracker.scoreOptions.enumerated().first { $0.offset == newValue }?.element.1
            guard state?.score != new else { return }
            state?.score = new
            update.score = new
            stateUpdated = true
        }
        .onChange(of: statusOption) { newValue in
            let new = tracker.supportedStatuses.count > newValue ?? 100 ? tracker.supportedStatuses[newValue!] : nil
            guard state?.status != new else { return }
            state?.status = new
            update.status = new
            stateUpdated = true
        }
        .onChange(of: lastReadChapter) { newValue in
            guard state?.lastReadChapter != newValue else { return }
            state?.lastReadChapter = newValue
            update.lastReadChapter = newValue
            stateUpdated = true
        }
        .onChange(of: lastReadVolume) { newValue in
            let new = newValue != nil ? Int(floor(newValue!)) : nil
            guard state?.lastReadVolume != new else { return }
            state?.lastReadVolume = new
            update.lastReadVolume = new
            stateUpdated = true
        }
        .onChange(of: startReadDate) { newValue in
            guard state?.startReadDate != newValue else { return }
            state?.startReadDate = newValue
            update.startReadDate = newValue == nil ? Date(timeIntervalSince1970: 0) : newValue
            stateUpdated = true
        }
        .onChange(of: finishReadDate) { newValue in
            guard state?.finishReadDate != newValue else { return }
            state?.finishReadDate = newValue
            update.finishReadDate = newValue == nil ? Date(timeIntervalSince1970: 0) : newValue
            stateUpdated = true
        }
        // fetch latest tracker state
        .onAppear {
            Task {
                state = await tracker.getState(trackId: item.id)
                guard let state = state else { return }

                withAnimation {
                    score = state.score != nil ? tracker.scoreType == .tenPointDecimal ? Float(state.score!) / 10 : Float(state.score!) : nil
                    if tracker.scoreType == .optionList {
                        let option = tracker.option(for: Int(state.score ?? 0))
                        scoreOption = tracker.scoreOptions.enumerated().first { $0.element.0 == option }?.offset
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
            if stateUpdated {
                Task {
                    await tracker.update(trackId: item.id, update: update)
                }
            }
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: $safariUrl)
        }
    }
}

struct SafariView: UIViewControllerRepresentable {
    @Binding var url: URL?
    func makeUIViewController(context: UIViewControllerRepresentableContext<SafariView>) -> SFSafariViewController {
        SFSafariViewController(url: url ?? URL(string: "about:blank")!)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SafariView>) {}
}

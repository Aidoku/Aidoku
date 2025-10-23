//
//  HistoryView.swift
//  Aidoku
//
//  Created by Skitty on 7/30/25.
//

import AidokuRunner
import LocalAuthentication
import SwiftUI
import SwiftUIIntrospect

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = ViewModel()

    @State private var searchText = ""
    @State private var entryToDelete: HistoryEntry?
    @State private var showClearHistoryConfirm = false
    @State private var showDeleteConfirm = false

    @State private var triggerLoadMoreVisibleCheck = false
    @State private var loadTask: Task<(), Never>?

    @State private var locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")

    @State private var listSelection: String? // fix for list highlighting being buggy

    @EnvironmentObject private var path: NavigationCoordinator

    var body: some View {
        Group {
            if locked {
                lockedView
            } else {
                List(selection: $listSelection) {
                    let sections = viewModel.filteredHistory.values.sorted { $0.daysAgo < $1.daysAgo }
                    ForEach(sections, id: \.daysAgo) { section in
                        if !section.entries.isEmpty {
                            Section {
                                ForEach(section.entries, id: \.chapterCacheKey) { entry in
                                    cellView(entry: entry)
                                }
                            } header: {
                                headerView(daysAgo: section.daysAgo)
                            }
                        }
                    }

                    loadMoreView
                }
                .listStyle(.grouped)
                .environment(\.defaultMinListRowHeight, 1)
                .environment(\.defaultMinListHeaderHeight, 1) // for ios 15
                .listSectionSpacingPlease(10)
                .scrollBackgroundHiddenPlease()
                .background(Color(uiColor: .systemBackground))
            }
        }
        .customSearchable(
            text: $searchText,
            onSubmit: {
                Task {
                    await viewModel.search(query: searchText, delay: false)
                }
            },
            onCancel: {
                Task {
                    await viewModel.search(query: searchText, delay: false)
                }
            }
        )
        .onChange(of: searchText) { newValue in
            Task {
                await viewModel.search(query: newValue, delay: true)
            }
        }
        .animation(.default, value: viewModel.filteredHistory)
        .navigationTitle(NSLocalizedString("HISTORY"))
        .navigationBarTitleDisplayMode(.automatic)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if UserDefaults.standard.bool(forKey: "History.lockHistoryTab") {
                    Button {
                        if locked {
                            unlock()
                        } else {
                            locked = true
                        }
                    } label: {
                        Image(systemName: locked ? "lock" : "lock.open")
                    }
                }
                Button {
                    showClearHistoryConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialogOrAlert(NSLocalizedString("CLEAR_READ_HISTORY"), isPresented: $showClearHistoryConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("CLEAR"), role: .destructive) {
                viewModel.clearHistory()
            }
        } message: {
            Text(NSLocalizedString("CLEAR_READ_HISTORY_TEXT"))
        }
        .confirmationDialogOrAlert(NSLocalizedString("CLEAR_READ_HISTORY"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                if let entryToDelete {
                    Task {
                        await viewModel.removeHistory(entry: entryToDelete)
                    }
                }
            }
            Button(NSLocalizedString("REMOVE_ALL_MANGA_HISTORY"), role: .destructive) {
                if let entryToDelete {
                    Task {
                        await viewModel.removeHistory(entry: entryToDelete, all: true)
                    }
                }
            }
        } message: {
            Text(NSLocalizedString("CLEAR_READ_HISTORY_TEXT"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyLockTabSetting)) { _ in
            // update locked state when the setting changes
            locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            // lock the view when the app is backgrounded
            locked = UserDefaults.standard.bool(forKey: "History.lockHistoryTab")
        }
    }

    var lockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("HISTORY_LOCKED"))
                .fontWeight(.medium)

            Button(NSLocalizedString("VIEW_HISTORY")) {
                unlock()
            }
        }
        .padding(.top, -52) // slight offset to account for search bar and make the view more centered
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func headerView(daysAgo: Int) -> some View {
        Text(Date.makeRelativeDate(days: daysAgo))
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .foregroundColor(.primary) // for ios 15
            .textCase(.none)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
    }

    func cellView(entry: HistoryEntry) -> some View {
        let manga = viewModel.mangaCache[entry.mangaCacheKey]
        let view = HistoryEntryCell(
            entry: entry,
            manga: manga,
            chapter: viewModel.chapterCache[entry.chapterCacheKey]
        ) {
            if let manga {
                path.push(MangaViewController(manga: manga, parent: path.rootViewController))
            }
        }
        .equatable()
        .contentShape(Rectangle())
        .listRowSeparator(.hidden, edges: .top)
        .listRowSeparator(.visible, edges: .bottom)
        .introspect(.listCell, on: .iOS(.v16, .v17, .v18, .v26)) { entity in
            // match cell background color to list background color when not selected (plain cell style)
            guard let cell = entity as? UICollectionViewListCell, cell.tag != 1 else { return }
            cell.backgroundConfiguration = UIBackgroundConfiguration.listPlainCell()
            cell.tag = 1
        }
        .swipeActions(edge: .trailing) {
            Button(NSLocalizedString("DELETE")) {
                entryToDelete = entry
                showDeleteConfirm = true
            }
            .tint(.red)
        }
        .id(entry.chapterCacheKey)
        .tag(entry.chapterCacheKey)

        if #available(iOS 16.0, *) {
            return view
                .alignmentGuide(.listRowSeparatorLeading) { d in
                    d[.leading]
                }
        } else {
            return view
        }
    }

    @ViewBuilder
    var loadMoreView: some View {
        VStack {
            if viewModel.loadingState != .complete {
                ProgressView()
                    .progressViewStyle(.circular)
                    .onReportScrollVisibilityChange(trigger: $triggerLoadMoreVisibleCheck) { visible in
                        Task {
                            await loadTask?.value
                            if visible {
                                tryLoadingMore()
                            }
                        }
                    }
                    .onChange(of: viewModel.filteredHistory) { _ in
                        // trigger check to see if the loading more view is still visible after content is added
                        Task {
                            try? await Task.sleep(nanoseconds: 10_000_000) // wait 10ms
                            triggerLoadMoreVisibleCheck = true
                        }
                    }
                    .onAppear {
                        tryLoadingMore()
                    }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(.zero)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // load more history entries if the loading state is idle
    func tryLoadingMore() {
        loadTask = Task {
            if viewModel.loadingState == .idle {
                await viewModel.loadMore()
            }
        }
    }

    // prompt for biometrics to unlock the view
    func unlock() {
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            let reason = NSLocalizedString("AUTH_FOR_HISTORY")

            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
                if success {
                    locked = false
                }
            }
        } else { // biometrics not supported
            locked = false
        }
    }
}

private struct HistoryEntryCell: View, Equatable {
    let entry: HistoryEntry

    let manga: AidokuRunner.Manga?
    let chapter: AidokuRunner.Chapter?

    var onPressed: (() -> Void)?

    private static let coverImageWidth: CGFloat = 56

    var body: some View {
        Button {
            onPressed?()
        } label: {
            HStack(spacing: 12) {
                MangaCoverView(
                    coverImage: manga?.cover ?? "",
                    width: Self.coverImageWidth,
                    height: Self.coverImageWidth * 3/2,
                    downsampleWidth: Self.coverImageWidth
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(manga?.title ?? "")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    Text(makeSubtitle())
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .lineLimit(1)
                    if let additionalEntryCount = entry.additionalEntryCount, additionalEntryCount > 0 {
                        let text = Text(String(format: NSLocalizedString("%lld_PLUS_MORE"), additionalEntryCount))
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .lineLimit(1)
                        if #available(iOS 16.0, *) {
                            text.contentTransition(.numericText())
                        } else {
                            text
                        }
                    }
                }
                Spacer()
            }
        }
        .tint(.primary)
    }

    func makeSubtitle() -> String {
        var components: [String] = []
        if let volumeNum = chapter?.volumeNumber, volumeNum >= 0 {
            if let chapterNum = chapter?.chapterNumber, chapterNum >= 0 {
                // both volume number and chapter number
                components.append([
                    String(format: NSLocalizedString("VOL_X"), volumeNum),
                    String(format: NSLocalizedString("CH_X"), chapterNum)
                ].joined(separator: " "))
            } else {
                // only volume number
                components.append(String(format: NSLocalizedString("VOL_SPACE_X"), volumeNum))
            }
        } else if let chapterNum = chapter?.chapterNumber, chapterNum >= 0 {
            // no volume number, just use chapter number
            components.append(String(format: NSLocalizedString("CH_SPACE_X"), chapterNum))
        } else if let title = chapter?.title, chapter?.chapterNumber == nil && chapter?.volumeNumber == nil {
            // no volume or chapter number, just use the title
            components.append(title)
        }
        if let currentPage = entry.currentPage, let totalPages = entry.totalPages, currentPage > 0, currentPage < totalPages {
            components.append(String(format: NSLocalizedString("PAGE_X_OF_X"), currentPage, totalPages))
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        components.append(formatter.string(from: entry.date))
        return components.joined(separator: " - ")
    }

    static func == (lhs: HistoryEntryCell, rhs: HistoryEntryCell) -> Bool {
        lhs.entry == rhs.entry && lhs.manga == rhs.manga && lhs.chapter == rhs.chapter
    }
}

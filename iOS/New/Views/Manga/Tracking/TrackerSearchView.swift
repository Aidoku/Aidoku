//
//  TrackerSearchView.swift
//  Aidoku
//
//  Created by Skitty on 7/29/25.
//

import AidokuRunner
import SwiftUI

struct TrackerSearchView: View {
    let tracker: Tracker
    let manga: AidokuRunner.Manga

    @State private var query: String
    @State private var includeNsfw: Bool

    @State private var loading = true
    @State private var searchBarFocused: Bool? = false
    @State private var showSearchOptions = false
    @State private var results: [TrackSearchItem] = []
    @State private var selectedItem: String?
    @State private var searchTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    init(tracker: Tracker, manga: AidokuRunner.Manga) {
        self.tracker = tracker
        self.manga = manga
        self._query = State(initialValue: manga.title)
        self._includeNsfw = State(initialValue: manga.contentRating != .safe)
    }

    var body: some View {
        PlatformNavigationStack {
            Group {
                if loading {
                    ProgressView().progressViewStyle(.circular)
                } else {
                    List {
                        ForEach(results, id: \.id) { item in
                            let view = Button {
                                if selectedItem == item.id {
                                    selectedItem = nil
                                } else {
                                    selectedItem = item.id
                                }
                            } label: {
                                TrackerSearchItemCell(item: item, selected: selectedItem == item.id)
                            }
                            if #available(iOS 16.0, *) {
                                view
                                    .alignmentGuide(.listRowSeparatorLeading) { d in
                                        d[.leading]
                                    }
                            } else {
                                view
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboardInteractively()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        if searchBarFocused == true {
                            searchBarFocused = false
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        track()
                    }
                    .disabled(selectedItem == nil)
                }
            }
            .sheet(isPresented: $showSearchOptions) {
                let view = TrackerSearchOptionsView(showNsfw: $includeNsfw)
                if #available(iOS 16.0, *) {
                    view.presentationDetents([.medium])
                } else {
                    view
                }
            }
            .animation(.default, value: loading)
            .animation(.default, value: results)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    results = try await tracker.search(for: manga, includeNsfw: includeNsfw)
                } catch {
                    LogManager.logger.error("Failed to search tracker \(tracker.id): \(error)")
                }
                loading = false
            }
            .onChange(of: query) { _ in
                guard !query.isEmpty else {
                    results = []
                    return
                }
                search(query: query, delay: true)
            }
            .onChange(of: includeNsfw) { _ in
                search(query: query, delay: false)
            }
            .customSearchable(
                text: $query,
                focused: $searchBarFocused,
                hideCancelButton: true,
                hidesNavigationBarDuringPresentation: false,
                hidesSearchBarWhenScrolling: false,
                bookmarkIcon: UIImage(systemName: "slider.horizontal.3")?
                    .withTintColor(.tintColor, renderingMode: .alwaysOriginal),
                onSubmit: {
                    if query.isEmpty {
                        results = []
                    } else {
                        search(query: query, delay: false)
                    }
                },
                onBookmarkPress: {
                    showSearchOptions = true
                }
            )
        }
    }

    func search(query: String, delay: Bool) {
        searchTask?.cancel()
        searchTask = Task {
            if delay {
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 second delay
            }
            guard !Task.isCancelled else { return }

            do {
                results = try await tracker.search(title: query, includeNsfw: includeNsfw)
            } catch {
                LogManager.logger.error("Failed to search tracker \(tracker.id): \(error)")
            }
        }
    }

    func track() {
        guard
            let selectedItem,
            let result = results.first(where: { $0.id == selectedItem })
        else { return }

        loading = true

        Task {
            await TrackerManager.shared.register(tracker: tracker, manga: manga, item: result)

            dismiss()
        }
    }
}

private struct TrackerSearchItemCell: View {
    let item: TrackSearchItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 16) {
            MangaCoverView(
                coverImage: item.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2,
                downsampleWidth: 56
            )
            VStack(alignment: .leading) {
                Text(item.title ?? "")
                    .lineLimit(2)
                if item.type != .unknown, let type = item.type?.toString() {
                    Text(String(format: NSLocalizedString("TYPE_COLON_%@", comment: ""), type))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if item.status != .unknown, let status = item.status?.toString() {
                    Text(String(format: NSLocalizedString("STATUS_COLON_%@", comment: ""), status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if item.tracked {
                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 10, height: 10)
            }
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.accentColor)
            }
        }
    }
}

private struct TrackerSearchOptionsView: View {
    @Binding var showNsfw: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Toggle(NSLocalizedString("SHOW_NSFW_RESULTS"), isOn: $showNsfw)
            }
            .navigationTitle(NSLocalizedString("SEARCH_OPTIONS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }
}

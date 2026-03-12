//
//  SettingsTrackingView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import AidokuRunner
import AuthenticationServices
import SwiftUI

struct SettingsTrackingView: View {
    @State private var trackers: [Tracker]
    @State private var trackersNeedingRelogin: Set<String> = []

    @State private var komgaSources: [AidokuRunner.Source] = []
    @State private var kavitaSources: [AidokuRunner.Source] = []
    @State private var enhancedTrackingStates: [String: Bool] = [:]

    @State private var loadedData = false
    @State private var loadingTrackerId: String?
    @State private var logoutTrackerName: String?
    @State private var showLogoutAlert = false

    private let iconSize: CGFloat = 42
    private let iconCornerRadius: CGFloat = 42 * 0.225

    // empty view controller to support login view presentation
    private static var loginShimController = LoginShimViewController()

    init() {
        self._trackers = State(initialValue: TrackerManager.trackers.filter { !($0 is EnhancedTracker) })
    }

    var body: some View {
        List {
            Section {
                SettingView(setting: .init(
                    key: "Tracking.updateAfterReading",
                    title: NSLocalizedString("UPDATE_AFTER_READING"),
                    value: .toggle(.init())
                ))
            } footer: {
                Text(NSLocalizedString("UPDATE_AFTER_READING_INFO"))
            }

            Section {
                SettingView(setting: .init(
                    key: "Tracking.autoSyncFromTracker",
                    title: NSLocalizedString("AUTO_SYNC_HISTORY"),
                    value: .toggle(.init())
                ))
            } footer: {
                Text(NSLocalizedString("AUTO_SYNC_HISTORY_INFO"))
            }

            Section(NSLocalizedString("TRACKERS")) {
                ForEach(trackers.indices, id: \.self) { index in
                    let tracker = trackers[index]
                    let needsRelogin = trackersNeedingRelogin.contains(tracker.id)
                    Button {
                        if tracker.isLoggedIn && !needsRelogin {
                            logoutTrackerName = tracker.name
                            showLogoutAlert = true
                        } else {
                            Task {
                                await login(to: tracker)
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = tracker.icon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: iconSize, height: iconSize)
                                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: iconCornerRadius)
                                            .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
                                    )
                            }
                            Text(tracker.name)
                                .foregroundStyle(.primary)
                                .tint(.primary)

                            Spacer()

                            if loadingTrackerId == tracker.id {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else if needsRelogin {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            } else if tracker.isLoggedIn {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .contextMenu {
                        if tracker.isLoggedIn {
                            Button {
                                Task {
                                    await login(to: tracker)
                                }
                            } label: {
                                Label(NSLocalizedString("REFRESH_LOGIN"), systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }
            }

            if !komgaSources.isEmpty || !kavitaSources.isEmpty {
                Section {
                    let items: [(tracker: Tracker, sources: [AidokuRunner.Source])] = [
                        (TrackerManager.komga, komgaSources),
                        (TrackerManager.kavita, kavitaSources)
                    ]
                    ForEach(items, id: \.tracker.id) { tracker, sources in
                        if !sources.isEmpty {
                            NavigationLink(destination: enhancedTrackerPage(name: tracker.name, sources: sources)) {
                                HStack(spacing: 12) {
                                    if let icon = tracker.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: iconSize, height: iconSize)
                                            .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: iconCornerRadius)
                                                    .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
                                            )
                                    }
                                    Text(tracker.name)
                                        .foregroundStyle(.primary)
                                        .tint(.primary)

                                    Spacer()
                                }
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("ENHANCED_TRACKERS"))
                } footer: {
                    Text(NSLocalizedString("ENHANCED_TRACKERS_INFO"))
                        .padding(.bottom, 8) // fix tab bar being too close to text on ios 26
                }
            }
        }
        .navigationTitle(NSLocalizedString("TRACKING"))
        .alert(String(format: NSLocalizedString("LOGOUT_FROM_%@"), logoutTrackerName ?? ""), isPresented: $showLogoutAlert) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("LOGOUT"), role: .destructive) {
                if let name = logoutTrackerName, let tracker = trackers.first(where: { $0.name == name }) {
                    Task {
                        // Call tracker logout to clear authentication data
                        do {
                            try await tracker.logout()

                            if let index = trackers.firstIndex(where: { $0.id == tracker.id }) {
                                trackers[index] = tracker
                            }
                        } catch {
                            LogManager.logger.error("Unable to log out from \(tracker.name) tracker: \(error)")
                        }
                        NotificationCenter.default.post(name: .updateTrackers, object: nil)
                        // Remove all tracked items for this tracker
                        await CoreDataManager.shared.container.performBackgroundTask { @Sendable context in
                            CoreDataManager.shared.removeTracks(trackerId: tracker.id, context: context)
                            try? context.save()
                        }
                    }
                }
            }
        } message: {
            Text(NSLocalizedString("TRACKER_LOGOUT_INFO"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateSourceList)) { _ in
            loadEnhancedTrackerSources()
        }
        .task {
            guard !loadedData else { return }

            for tracker in trackers {
                guard let oauthTracker = tracker as? OAuthTracker else { return }
                let needsRelogin = await oauthTracker.oauthClient.tokens?.askedForRefresh == true
                if needsRelogin {
                    trackersNeedingRelogin.insert(tracker.id)
                }
            }

            loadEnhancedTrackerSources()

            loadedData = true
        }
    }

    func enhancedTrackerPage(name: String, sources: [AidokuRunner.Source]) -> some View {
        List {
            Section {
                ForEach(sources) { source in
                    HStack(spacing: 12) {
                        SourceIconView(sourceId: source.key, imageUrl: source.imageUrl)

                        Text(source.name)
                            .foregroundStyle(.primary)
                            .tint(.primary)

                        Spacer()

                        Toggle(isOn: stateBinding(sourceKey: source.id)) {
                            EmptyView()
                        }
                    }
                }
            } footer: {
                Text(NSLocalizedString("ENHANCED_TRACKERS_TOGGLE_INFO"))
            }
        }
        .navigationTitle(name)
    }
}

extension SettingsTrackingView {
    func loadEnhancedTrackerSources() {
        var komgaSources: [AidokuRunner.Source] = []
        var kavitaSources: [AidokuRunner.Source] = []
        for source in SourceManager.shared.sources {
            if source.key.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                komgaSources.append(source)
            } else if source.key.hasPrefix(KavitaSourceRunner.sourceKeyPrefix) {
                kavitaSources.append(source)
            }
        }
        var enhancedTrackingStates: [String: Bool] = [:]
        for source in (komgaSources + kavitaSources) {
            let trackingDisabled = UserDefaults.standard.bool(forKey: "\(source.key).disableTracking")
            enhancedTrackingStates[source.key] = !trackingDisabled
        }
        self.komgaSources = komgaSources
        self.kavitaSources = kavitaSources
        self.enhancedTrackingStates = enhancedTrackingStates
    }

    func handleEnhancedTrackingStateChange(sourceKey: String, enabled: Bool) {
        UserDefaults.standard.set(!enabled, forKey: "\(sourceKey).disableTracking")
        Task {
            let tracker: EnhancedTracker
            if sourceKey.hasPrefix(KomgaSourceRunner.sourceKeyPrefix) {
                tracker = TrackerManager.komga
            } else if sourceKey.hasPrefix(KavitaSourceRunner.sourceKeyPrefix) {
                tracker = TrackerManager.kavita
            } else {
                return
            }
            if enabled {
                // enable tracking for all items in library
                let libraryManga = await CoreDataManager.shared.container.performBackgroundTask { context in
                    let manga = CoreDataManager.shared.getLibraryManga(sourceId: sourceKey, context: context)
                    return manga.compactMap { $0.manga?.toNewManga() }
                }
                for manga in libraryManga {
                    guard
                        tracker.canRegister(sourceKey: manga.sourceKey, mangaKey: manga.key)
                    else {
                        continue
                    }
                    do {
                        let items = try await tracker.search(for: manga, includeNsfw: true)
                        guard let item = items.first else {
                            LogManager.logger.error("Unable to find track item from tracker \(tracker.id)")
                            return
                        }
                        await TrackerManager.shared.register(tracker: tracker, manga: manga, item: item)
                    } catch {
                        LogManager.logger.error("Unable to find track item from tracker \(tracker.id): \(error)")
                    }
                }
            } else {
                // remove existing linked trackers on all items
                guard let source = SourceManager.shared.source(for: sourceKey) else { return }
                do {
                    try await tracker.removeTrackItems(source: source)
                } catch {
                    LogManager.logger.error("Unable to remove tracker items from source: \(error)")
                }
            }
        }
    }

    func login(to tracker: Tracker) async {
        if let tracker = tracker as? OAuthTracker {
            guard let url = await tracker.getAuthenticationUrl() else { return }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "aidoku") { callbackURL, error in
                if let error {
                    LogManager.logger.error("Tracker authentication error: \(error.localizedDescription)")
                }
                if let callbackURL {
                    Task { @MainActor in
                        let loadingIndicator = UIActivityIndicatorView(style: .medium)
                        loadingIndicator.startAnimating()

                        loadingTrackerId = tracker.id
                        await tracker.handleAuthenticationCallback(url: callbackURL)
                        loadingTrackerId = nil

                        if let index = trackers.firstIndex(where: { $0.id == tracker.id }) {
                            trackers[index] = tracker
                        }

                        if tracker.isLoggedIn {
                            await tracker.oauthClient.loadTokens()
                            trackersNeedingRelogin.remove(tracker.id)
                        }

                        NotificationCenter.default.post(name: .updateTrackers, object: nil)
                    }
                }
            }
            session.presentationContextProvider = Self.loginShimController
            session.start()
        }
    }
}

extension SettingsTrackingView {
    func stateBinding(sourceKey: String) -> Binding<Bool> {
        Binding {
            enhancedTrackingStates[sourceKey, default: true]
        } set: {
            enhancedTrackingStates[sourceKey] = $0
            handleEnhancedTrackingStateChange(sourceKey: sourceKey, enabled: $0)
        }
    }
}

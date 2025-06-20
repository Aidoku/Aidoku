//
//  SourceSettingsView.swift
//  Aidoku
//
//  Created by Skitty on 10/6/23.
//

import SwiftUI
import AidokuRunner

struct SourceSettingsView: View {
    let source: AidokuRunner.Source

    @State private var settings: [Setting] = []
    @State private var showingResetAlert = false
    @State private var error: Error?

    @EnvironmentObject var path: NavigationCoordinator

    init(source: AidokuRunner.Source) {
        self.source = source
        if !source.features.dynamicSettings {
            self._settings = State(initialValue: source.staticSettings)
        }
    }

    var body: some View {
        List {
            // header
            Section {
                SourceTableCell(source: source)
                    .listRowInsets(.init(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
            .listRowBackground(
                Color(uiColor: .secondarySystemGroupedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )

            // source settings
            if let error {
                Section {
                    ErrorView(error: error) {
                        Task {
                            await loadSettings()
                        }
                    }
                    .padding()
                    frame(maxWidth: .infinity)
                }
            } else if !settings.isEmpty {
                ForEach(Array(settings.enumerated()), id: \.offset) { _, setting in
                    SettingView(source: source, setting: setting, namespace: source.id)
                }
            }

            // reset button
            if !settings.isEmpty || source.languages.count > 1 {
                Section {
                    Button(NSLocalizedString("RESET_SETTINGS")) {
                        showingResetAlert = true
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("SOURCE_SETTINGS"))
        // for ios 15
        .background(
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.dismiss()
                } label: {
                    Text(NSLocalizedString("DONE")).bold()
                }
            }
        }
        .animation(.default, value: settings)
        .task {
            guard settings.isEmpty else { return }
            await loadSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("refresh-settings"))) { _ in
            Task {
                await loadSettings()
            }
        }
        .alert(NSLocalizedString("RESET_SETTINGS"), isPresented: $showingResetAlert) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("RESET"), role: .destructive) {
                resetSettings()
            }
        } message: {
            Text(String(format: NSLocalizedString("RESET_SETTINGS_CONFIRM_%@"), source.name))
        }
    }

    func loadSettings() async {
        withAnimation {
            error = nil
        }
        do {
            settings = try await source.getSettings()
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }

    // find every userdefaults key with the source id as the prefix and remove it
    func resetSettings() {
        let userDefaults = UserDefaults.standard
        let keys = userDefaults.dictionaryRepresentation().keys

        for key in keys where key.hasPrefix(source.id) {
            userDefaults.removeObject(forKey: key)
        }

        let currentSettings = settings
        settings = []
        settings = currentSettings

        for name in ["refresh-content", "refresh-settings"] {
            NotificationCenter.default.post(name: .init(name), object: nil)
        }
    }
}

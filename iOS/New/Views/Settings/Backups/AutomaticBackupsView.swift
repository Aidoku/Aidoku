//
//  AutomaticBackupsView.swift
//  Aidoku
//
//  Created by Skitty on 11/13/25.
//

import SwiftUI

struct AutomaticBackupsView: View {
    @State private var enabled: Bool
    @State private var libraryEntries: Bool
    @State private var chapters: Bool
    @State private var tracking: Bool
    @State private var history: Bool
    @State private var categories: Bool
    @State private var settings: Bool
    @State private var sourceLists: Bool
    @State private var sensitiveSettings: Bool

    @Environment(\.dismiss) private var dismiss

    init() {
        self._enabled = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.enabled"))
        self._libraryEntries = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.libraryEntries"))
        self._chapters = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.chapters"))
        self._tracking = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.tracking"))
        self._history = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.history"))
        self._categories = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.categories"))
        self._settings = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.settings"))
        self._sourceLists = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.sourceLists"))
        self._sensitiveSettings = State(initialValue: UserDefaults.standard.bool(forKey: "AutomaticBackups.sensitiveSettings"))
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    Toggle(NSLocalizedString("AUTOMATIC_BACKUPS"), isOn: $enabled)

                    if enabled {
                        SettingView(
                            setting: .init(
                                key: "AutomaticBackups.interval",
                                title: NSLocalizedString("BACKUP_INTERVAL"),
                                value: .select(.init(
                                    values: ["6hours", "12hours", "daily", "2days", "weekly"],
                                    titles: [
                                        NSLocalizedString("EVERY_6_HOURS"),
                                        NSLocalizedString("EVERY_12_HOURS"),
                                        NSLocalizedString("DAILY"),
                                        NSLocalizedString("EVERY_2_DAYS"),
                                        NSLocalizedString("WEEKLY")
                                    ]
                                ))
                            )
                        )
                    }
                } footer: {
                    let date = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "AutomaticBackups.lastBackup"))
                    if date > Date.distantPast {
                        Text(String(format: NSLocalizedString("LAST_BACKED_UP_%@"), date.formatted(.relative(presentation: .named))))
                    }
                }

                if enabled {
                    Section(NSLocalizedString("LIBRARY")) {
                        Toggle(NSLocalizedString("LIBRARY_ENTRIES"), isOn: $libraryEntries)
                        Toggle(NSLocalizedString("CHAPTERS"), isOn: $chapters)
                        Toggle(NSLocalizedString("TRACKING"), isOn: $tracking)
                        Toggle(NSLocalizedString("HISTORY"), isOn: $history)
                        Toggle(NSLocalizedString("CATEGORIES"), isOn: $categories)
                    }
                    Section(NSLocalizedString("SETTINGS")) {
                        Toggle(NSLocalizedString("SETTINGS"), isOn: $settings)
                        Toggle(NSLocalizedString("SOURCE_LISTS"), isOn: $sourceLists)
                        Toggle(NSLocalizedString("SENSITIVE_SETTINGS"), isOn: $sensitiveSettings)
                    }
                }
            }
            .animation(.default, value: enabled)
            .navigationTitle(NSLocalizedString("AUTOMATIC_BACKUPS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        dismiss()
                    }
                }
            }
            .onChange(of: enabled) { _ in
                Task {
                    await BackupManager.shared.scheduleAutoBackup()
                }
            }
        }
    }
}

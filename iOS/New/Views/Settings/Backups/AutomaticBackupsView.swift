//
//  AutomaticBackupsView.swift
//  Aidoku
//
//  Created by Skitty on 11/13/25.
//

import SwiftUI

struct AutomaticBackupsView: View {
    @StateObject private var enabled = UserDefaultsBool(key: "AutomaticBackups.enabled")

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    toggle(key: "AutomaticBackups.enabled", title: NSLocalizedString("AUTOMATIC_BACKUPS"))

                    if enabled.value {
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

                if enabled.value {
                    Section(NSLocalizedString("LIBRARY")) {
                        toggle(key: "AutomaticBackups.libraryEntries", title: NSLocalizedString("LIBRARY_ENTRIES"))
                        toggle(key: "AutomaticBackups.chapters", title: NSLocalizedString("CHAPTERS"))
                        toggle(key: "AutomaticBackups.tracking", title: NSLocalizedString("TRACKING"))
                        toggle(key: "AutomaticBackups.history", title: NSLocalizedString("HISTORY"))
                        toggle(key: "AutomaticBackups.categories", title: NSLocalizedString("CATEGORIES"))
                        toggle(key: "AutomaticBackups.readingSessions", title: NSLocalizedString("READING_SESSIONS"))
                        toggle(key: "AutomaticBackups.updates", title: NSLocalizedString("UPDATES"))
                    }
                    Section(NSLocalizedString("SETTINGS")) {
                        toggle(key: "AutomaticBackups.settings", title: NSLocalizedString("SETTINGS"))
                        toggle(key: "AutomaticBackups.sourceLists", title: NSLocalizedString("SOURCE_LISTS"))
                        toggle(key: "AutomaticBackups.sensitiveSettings", title: NSLocalizedString("SENSITIVE_SETTINGS"))
                    }
                }
            }
            .animation(.default, value: enabled.value)
            .navigationTitle(NSLocalizedString("AUTOMATIC_BACKUPS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .onChange(of: enabled.value) { _ in
                Task {
                    await BackupManager.shared.scheduleAutoBackup()
                }
            }
        }
    }

    func toggle(key: String, title: String) -> some View {
        SettingView(
            setting: .init(
                key: key,
                title: title,
                value: .toggle(.init())
            )
        )
    }
}

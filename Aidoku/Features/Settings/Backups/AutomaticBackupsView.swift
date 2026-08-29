//
//  AutomaticBackupsView.swift
//  Aidoku
//
//  Created by Skitty on 11/13/25.
//

import SwiftUI

struct AutomaticBackupsView: View {
    @StateObject private var enabled = UserDefaultsBool(key: AppSettings.backups.autoBackups.enabled.key)

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    toggle(key: AppSettings.backups.autoBackups.enabled.key, title: NSLocalizedString("AUTOMATIC_BACKUPS"))

                    if enabled.value {
                        SettingView(
                            setting: .init(
                                key: AppSettings.backups.autoBackups.interval.key,
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
                    let date = AppSettings.backups.autoBackups.lastBackup.get()
                    if date > Date.distantPast {
                        Text(String(format: NSLocalizedString("LAST_BACKED_UP_%@"), date.formatted(.relative(presentation: .named))))
                    }
                }

                if enabled.value {
                    Section(NSLocalizedString("LIBRARY")) {
                        toggle(key: AppSettings.backups.autoBackups.libraryEntries.key, title: NSLocalizedString("LIBRARY_ENTRIES"))
                        toggle(key: AppSettings.backups.autoBackups.chapters.key, title: NSLocalizedString("CHAPTERS"))
                        toggle(key: AppSettings.backups.autoBackups.tracking.key, title: NSLocalizedString("TRACKING"))
                        toggle(key: AppSettings.backups.autoBackups.history.key, title: NSLocalizedString("HISTORY"))
                        toggle(key: AppSettings.backups.autoBackups.categories.key, title: NSLocalizedString("CATEGORIES"))
                        toggle(key: AppSettings.backups.autoBackups.readingSessions.key, title: NSLocalizedString("READING_SESSIONS"))
                        toggle(key: AppSettings.backups.autoBackups.vocabulary.key, title: NSLocalizedString("VOCABULARY"))
                        toggle(key: AppSettings.backups.autoBackups.updates.key, title: NSLocalizedString("MANGA_UPDATES"))
                    }
                    Section(NSLocalizedString("SETTINGS")) {
                        toggle(key: AppSettings.backups.autoBackups.settings.key, title: NSLocalizedString("SETTINGS"))
                        toggle(key: AppSettings.backups.autoBackups.sourceLists.key, title: NSLocalizedString("SOURCE_LISTS"))
                        toggle(key: AppSettings.backups.autoBackups.sensitiveSettings.key, title: NSLocalizedString("SENSITIVE_SETTINGS"))
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

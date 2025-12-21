//
//  BackupCreateView.swift
//  Aidoku
//
//  Created by Skitty on 9/28/25.
//

import SwiftUI

struct BackupCreateView: View {
    @State private var libraryEntries = true
    @State private var chapters = true
    @State private var tracking = true
    @State private var history = true
    @State private var readingSessions = true
    @State private var updates = false
    @State private var categories = true
    @State private var settings = true
    @State private var sourceLists = true
    @State private var sensitiveSettings = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    Toggle(NSLocalizedString("LIBRARY_ENTRIES"), isOn: $libraryEntries)
                    Toggle(NSLocalizedString("CHAPTERS"), isOn: $chapters)
                    Toggle(NSLocalizedString("TRACKING"), isOn: $tracking)
                    Toggle(NSLocalizedString("HISTORY"), isOn: $history)
                    Toggle(NSLocalizedString("CATEGORIES"), isOn: $categories)
                    Toggle(NSLocalizedString("READING_SESSIONS"), isOn: $readingSessions)
                    Toggle(NSLocalizedString("UPDATES"), isOn: $updates)
                } header: {
                    Text(NSLocalizedString("LIBRARY"))
                }
                Section {
                    Toggle(NSLocalizedString("SETTINGS"), isOn: $settings)
                    Toggle(NSLocalizedString("SOURCE_LISTS"), isOn: $sourceLists)
                    Toggle(NSLocalizedString("SENSITIVE_SETTINGS"), isOn: $sensitiveSettings)
                } header: {
                    Text(NSLocalizedString("SETTINGS"))
                }
            }
            .navigationTitle(NSLocalizedString("CREATE_BACKUP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DoneButton {
                        Task {
                            await BackupManager.shared.saveNewBackup(options: .init(
                                libraryEntries: libraryEntries,
                                history: history,
                                chapters: chapters,
                                tracking: tracking,
                                readingSessions: readingSessions,
                                updates: updates,
                                categories: categories,
                                settings: settings,
                                sourceLists: sourceLists,
                                sensitiveSettings: sensitiveSettings
                            ))
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

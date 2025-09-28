//
//  BackupContentView.swift
//  Aidoku
//
//  Created by Skitty on 9/28/25.
//

import SwiftUI

struct BackupContentView: View {
    let backup: Backup

    @State private var restoreError: String?
    @State private var missingSources: [String] = []
    @State private var showRestoreAlert = false
    @State private var showRestoreErrorAlert = false
    @State private var showMissingSourcesAlert = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            List {
                Section {
                    infoCell(title: NSLocalizedString("NAME"), value: backup.name ?? NSLocalizedString("NONE"))
                    infoCell(
                        title: NSLocalizedString("DATE"),
                        value: backup.date.formatted(date: .numeric, time: .shortened)
                    )
                }
                Section {
                    infoCell(
                        title: NSLocalizedString("LIBRARY_ENTRIES"),
                        value: String(backup.library?.count ?? 0)
                    )
                    infoCell(
                        title: NSLocalizedString("HISTORY"),
                        value: String(backup.history?.count ?? 0)
                    )
                    infoCell(
                        title: NSLocalizedString("CHAPTERS"),
                        value: String(backup.chapters?.count ?? 0)
                    )
                    infoCell(
                        title: NSLocalizedString("TRACKING"),
                        value: String(backup.trackItems?.count ?? 0)
                    )
                    infoCell(
                        title: NSLocalizedString("CATEGORIES"),
                        value: String(backup.categories?.count ?? 0)
                    )
                    infoCell(
                        title: NSLocalizedString("SETTINGS"),
                        value: String(backup.settings?.count ?? 0)
                    )
                }

                Section {
                    LargeButton {
                        showRestoreAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "gearshape.arrow.trianglehead.2.clockwise.rotate.90")
                            Text(NSLocalizedString("RESTORE"))
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("BACKUP_INFO_TITLE"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("RESTORE_BACKUP"), isPresented: $showRestoreAlert) {
                Button(NSLocalizedString("CANCEL"), role: .cancel) {}
                Button(NSLocalizedString("RESTORE"), role: .destructive) {
                    restore()
                }
            } message: {
                Text(NSLocalizedString("RESTORE_BACKUP_TEXT"))
            }
            .alert(NSLocalizedString("BACKUP_ERROR"), isPresented: $showRestoreErrorAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(String(format: NSLocalizedString("BACKUP_ERROR_TEXT"), restoreError ?? NSLocalizedString("UNKNOWN")))
            }
            .alert(NSLocalizedString("MISSING_SOURCES"), isPresented: $showMissingSourcesAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("MISSING_SOURCES_TEXT") + missingSources.map { "\n- \($0)" }.joined())
            }
        }
    }

    func infoCell(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .lineLimit(1)
            Spacer()
            Text(value)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }

    func restore() {
        (UIApplication.shared.delegate as? AppDelegate)?.showLoadingIndicator()
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            do {
                try await BackupManager.shared.restore(from: backup)
                (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()

                let missingSources = (backup.sources ?? []).filter {
                    !CoreDataManager.shared.hasSource(id: $0)
                }
                if !missingSources.isEmpty {
                    self.missingSources = missingSources
                    showMissingSourcesAlert = true
                }
            } catch {
                (UIApplication.shared.delegate as? AppDelegate)?.hideLoadingIndicator()

                restoreError = (error as? BackupManager.BackupError)?.stringValue ?? "Unknown"
                showRestoreErrorAlert = true
            }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

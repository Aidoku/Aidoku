//
//  BackupsView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct BackupsView: View {
    @State private var backupUrls: [URL] = []
    @State private var backups: [URL: Backup] = [:]
    @State private var invalidBackups: Set<URL> = []

    @State private var loadedInitialBackupInfo = false
    @State private var targetRestoreBackup: Backup?
    @State private var targetRenameBackupUrl: URL?
    @State private var backupName: String = ""
    @State private var showCreateSheet = false
    @State private var showRenameAlert = false

    @EnvironmentObject private var path: NavigationCoordinator

    init() {
        self._backupUrls = State(initialValue: BackupManager.backupUrls)
    }

    var body: some View {
        List {
            Section {
                ForEach(backupUrls, id: \.self) { url in
                    let backup = backups[url]

                    if let backup {
                        Button {
                            targetRestoreBackup = backup
                        } label: {
                            HStack {
                                let date = DateFormatter.localizedString(from: backup.date, dateStyle: .short, timeStyle: .short)
                                if let name = backup.name {
                                    VStack(alignment: .leading) {
                                        Text(name)
                                            .lineLimit(1)
                                        Text(date)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(String(format: NSLocalizedString("BACKUP_%@"), date))
                                }
                                Spacer()
                                if
                                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                                    let size = attributes[FileAttributeKey.size] as? Int64
                                {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .foregroundStyle(.secondary)
                                        .font(.footnote)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button(role: .destructive) {
                                onDelete(at: IndexSet(integer: backupUrls.firstIndex(of: url)!))
                            } label: {
                                Label(NSLocalizedString("DELETE"), systemImage: "trash")
                            }
                            Button {
                                targetRenameBackupUrl = url
                                backupName = backup.name ?? ""
                                showRenameAlert = true
                            } label: {
                                Label(NSLocalizedString("RENAME"), systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button {
                                export(url: url)
                            } label: {
                                Label(NSLocalizedString("EXPORT"), systemImage: "square.and.arrow.up")
                            }
                        }
                    } else if invalidBackups.contains(url) {
                        Text(NSLocalizedString("CORRUPTED_BACKUP"))
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                .onDelete(perform: onDelete)
            } footer: {
                if !backupUrls.isEmpty {
                    Text(NSLocalizedString("BACKUP_INFO"))
                }
            }
        }
        .animation(.default, value: backupUrls)
        .animation(.default, value: backups)
        .navigationTitle(NSLocalizedString("BACKUPS"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            BackupCreateView()
        }
        .sheet(item: $targetRestoreBackup) { backup in
            BackupContentView(backup: backup)
        }
        .alert(NSLocalizedString("RENAME_BACKUP"), isPresented: $showRenameAlert) {
            TextField(NSLocalizedString("BACKUP_NAME"), text: $backupName)
                .autocorrectionDisabled()
                .submitLabel(.done)
            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                backupName = ""
            }
            Button(NSLocalizedString("OK")) {
                if let targetRenameBackupUrl {
                    renameBackup(url: targetRenameBackupUrl, name: backupName)
                }
                backupName = ""
            }
        } message: {
            Text(NSLocalizedString("RENAME_BACKUP_TEXT"))
        }
        .onAppear {
            guard !loadedInitialBackupInfo else { return }
            loadedInitialBackupInfo = true
            loadBackupInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateBackupList)) { _ in
            backupUrls = BackupManager.backupUrls
            loadBackupInfo()
        }
    }

    func onDelete(at offsets: IndexSet) {
        for offset in offsets {
            let url = backupUrls[offset]
            BackupManager.shared.removeBackup(url: url)
            backups.removeValue(forKey: url)
        }
        backupUrls.remove(atOffsets: offsets)
    }
}

extension BackupsView {
    func loadBackupInfo() {
        Task.detached { [backupUrls] in
            for backupUrl in backupUrls {
                let backup = Backup.load(from: backupUrl)
                await MainActor.run {
                    if let backup {
                        self.backups[backupUrl] = backup
                    } else {
                        self.invalidBackups.insert(backupUrl)
                    }
                }
            }
        }
    }

    func renameBackup(url: URL, name: String) {
        BackupManager.shared.renameBackup(url: url, name: name)
    }

    func export(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let sourceView = path.rootViewController?.view else { return }
        vc.popoverPresentationController?.sourceView = sourceView
        path.present(vc)
    }
}

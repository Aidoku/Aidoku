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
    @State private var showCreateSheet = false
    @State private var showAutoBackupsSheet = false

    @EnvironmentObject private var path: NavigationCoordinator

    @Namespace private var transitionNamespace

    private enum SheetID: String {
        case create
        case autoBackup
    }

    init() {
        self._backupUrls = State(initialValue: BackupManager.backupUrls)
    }

    var body: some View {
        let list = List {
            Section {
                ForEach(backupUrls, id: \.self) { url in
                    let backup = backups[url]

                    if let backup {
                        backupCell(url: url, backup: backup)
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
        .sheet(isPresented: $showCreateSheet) {
            BackupCreateView()
                .navigationTransitionZoom(sourceID: SheetID.create, in: transitionNamespace)
        }
        .sheet(isPresented: $showAutoBackupsSheet) {
            AutomaticBackupsView()
                .navigationTransitionZoom(sourceID: SheetID.autoBackup, in: transitionNamespace)
        }
        .sheet(item: $targetRestoreBackup) { backup in
            BackupContentView(backup: backup)
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

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        autoBackupButton
                        createBackupButton
                    }
                }
        }
    }

    var autoBackupButton: some View {
        Button {
            showAutoBackupsSheet = true
        } label: {
            let imageName = if #available(iOS 18.0, *) {
                "clock.arrow.trianglehead.counterclockwise.rotate.90"
            } else {
                "clock.arrow.circlepath"
            }
            Image(systemName: imageName)
        }
        .matchedTransitionSourcePlease(id: SheetID.autoBackup, in: transitionNamespace)
    }

    var createBackupButton: some View {
        Button {
            showCreateSheet = true
        } label: {
            Image(systemName: "plus")
        }
        .matchedTransitionSourcePlease(id: SheetID.create, in: transitionNamespace)
    }

    @available(iOS 26.0, *)
    @ToolbarContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            autoBackupButton
        }

        ToolbarSpacer(placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            createBackupButton
        }
    }

    func backupCell(url: URL, backup: Backup) -> some View {
        Button {
            targetRestoreBackup = backup
        } label: {
            HStack {
                let date = DateFormatter.localizedString(from: backup.date, dateStyle: .short, timeStyle: .short)
                if let name = backup.name {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(name)
                                .lineLimit(1)
                            if backup.automatic ?? false {
                                automaticBadge
                            }
                        }
                        Text(date)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text(String(format: NSLocalizedString("BACKUP_%@"), date))
                            .lineLimit(1)
                        if backup.automatic ?? false {
                            automaticBadge
                        }
                    }
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
                showRenamePrompt(targetRenameBackupUrl: url, initialName: backup.name)
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
    }

    var automaticBadge: some View {
        Text(NSLocalizedString("AUTO"))
            .lineLimit(1)
            .foregroundStyle(.primary)
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.blue.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func onDelete(at offsets: IndexSet) {
        for offset in offsets {
            let url = backupUrls[offset]
            Task {
                await BackupManager.shared.removeBackup(url: url)
            }
            backups.removeValue(forKey: url)
        }
        backupUrls.remove(atOffsets: offsets)
    }

    func showRenamePrompt(targetRenameBackupUrl: URL, initialName: String?) {
        var alertTextField: UITextField?
        (UIApplication.shared.delegate as? AppDelegate)?.presentAlert(
            title: NSLocalizedString("RENAME_BACKUP"),
            message: NSLocalizedString("RENAME_BACKUP_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    renameBackup(url: targetRenameBackupUrl, name: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("BACKUP_NAME")
                    textField.text = initialName
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
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
        Task {
            await BackupManager.shared.renameBackup(url: url, name: name)
        }
    }

    func export(url: URL) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let sourceView = path.rootViewController?.view else { return }
        vc.popoverPresentationController?.sourceView = sourceView
        path.present(vc)
    }
}

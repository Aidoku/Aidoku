//
//  SourceListsView.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import SwiftUI

struct SourceListsView: View {
    @State private var sourceLists: [SourceList] = []
    @State private var missingSourceLists: [URL] = []

    @State private var loading = true
    @State private var showAddListFailAlert = false

    var body: some View {
        List {
            Section {
                ForEach(sourceLists, id: \.url) { sourceList in
                    listItem(name: sourceList.name, url: sourceList.url)
                }
                .onDelete(perform: delete)
            }

            if !missingSourceLists.isEmpty {
                Section {
                    ForEach(missingSourceLists, id: \.self) { url in
                        listItem(url: url)
                    }
                } header: {
                    Text(NSLocalizedString("UNAVAILABLE_SOURCE_LISTS"))
                } footer: {
                    Text(NSLocalizedString("UNAVAILABLE_SOURCE_LISTS_TEXT"))
                }
            }
        }
        .overlay {
            if loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.secondary)
            }
        }
        .navigationTitle(NSLocalizedString("SOURCE_LISTS"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAlert()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("SOURCE_LIST_ADD_FAIL"), isPresented: $showAddListFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateSourceLists)) { _ in
            Task {
                await loadSourceLists()
            }
        }
        .task {
            guard sourceLists.isEmpty else { return }
            await loadSourceLists()
        }
    }

    func loadSourceLists() async {
        withAnimation {
            loading = true
        }
        let newSourceLists = await SourceManager.shared.getSourceLists()
        let newMissingSourceLists = await SourceManager.shared.getMissingSourceLists()
        withAnimation {
            sourceLists = newSourceLists
            missingSourceLists = newMissingSourceLists
            loading = false
        }
    }

    func listItem(name: String? = nil, url: URL) -> some View {
        VStack(alignment: .leading) {
            if let name {
                Text(name)
            }
            Text(url.absoluteString)
                .lineLimit(1)
                .font(.subheadline)
                .foregroundStyle(name == nil ? .primary : .secondary)
        }
        .contextMenu {
            Button(role: .destructive) {
                sourceLists.firstIndex(where: { $0.url == url }).flatMap {
                    _ = sourceLists.remove(at: $0)
                }
                missingSourceLists.firstIndex(of: url).flatMap {
                    _ = missingSourceLists.remove(at: $0)
                }
                Task {
                    await SourceManager.shared.removeSourceList(url: url)
                }
            } label: {
                Label(NSLocalizedString("REMOVE"), systemImage: "trash")
            }
            Button {
                UIPasteboard.general.string = url.absoluteString
            } label: {
                Label(NSLocalizedString("COPY_URL"), systemImage: "doc.on.doc")
            }
        }
    }

    func delete(at offsets: IndexSet) {
        let urls = offsets.map { sourceLists[$0].url }
        Task {
            for url in urls {
                await SourceManager.shared.removeSourceList(url: url)
            }
        }
    }

    func addSourceList(url: String) {
        guard !url.isEmpty else { return }
        guard let url = URL(string: url) else {
            showAddListFailAlert = true
            return
        }

        actor Done {
            var value: Bool = false
            func set() {
                value = true
            }
        }
        let done = Done()

        Task {
            // show loading indicator if it takes longer than 0.5s
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let finished = await done.value
                if !finished {
                    await MainActor.run {
                        UIApplication.shared.appDelegate?.showLoadingIndicator()
                    }
                }
            }

            let success = await SourceManager.shared.addSourceList(url: url)
            await done.set()
            await UIApplication.shared.appDelegate?.hideLoadingIndicator()

            if success {
                await loadSourceLists()
            } else {
                showAddListFailAlert = true
            }
        }
    }

    func showAlert() {
        var alertTextField: UITextField?
        UIApplication.shared.appDelegate?.presentAlert(
            title: NSLocalizedString("SOURCE_LIST_ADD"),
            message: NSLocalizedString("SOURCE_LIST_ADD_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text, !text.isEmpty else { return }
                    addSourceList(url: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("SOURCE_LIST_URL")
                    textField.keyboardType = .URL
                    textField.autocorrectionType = .no
                    textField.autocapitalizationType = .none
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ]
        )
    }
}

#Preview {
    SourceListsView()
}

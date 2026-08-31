//
//  SourceListsView.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import SwiftUI

struct SourceListsView: View {
    @State private var sourceListsURLs: [URL] = []
    @State private var sourceLists: [URL: SourceList] = [:]
    @State private var missingSourceLists: Set<URL> = []
    @State private var showAddListFailAlert = false

    private var activeSourceListURLs: [URL] {
        sourceListsURLs.filter {
            !missingSourceLists.contains($0)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(activeSourceListURLs, id: \.self) { url in
                    if let sourceList = sourceLists[url] {
                        listItem(name: sourceList.name, url: sourceList.url)
                    } else {
                        listItem(url: url, loading: true)
                    }
                }
                .onDelete(perform: delete)
            }

            if !missingSourceLists.isEmpty {
                Section {
                    ForEach(sourceListsURLs, id: \.self) { url in
                        if missingSourceLists.contains(url) {
                            listItem(url: url)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("UNAVAILABLE_SOURCE_LISTS"))
                } footer: {
                    Text(NSLocalizedString("UNAVAILABLE_SOURCE_LISTS_TEXT"))
                }
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
        sourceListsURLs = await SourceManager.shared.getSourceListURLs().sorted { $0.absoluteString < $1.absoluteString }

        if await SourceManager.shared.sourceListLoadFinished {
            missingSourceLists = await SourceManager.shared.getMissingSourceLists()
            sourceLists = await SourceManager.shared.getLoadedSourceLists()
        } else {
            missingSourceLists = []
            sourceLists = [:]

            let stream = await SourceManager.shared.streamSourceListsLoad()
            for await url in stream {
                let sourceList = await SourceManager.shared.getSourceList(url: url)
                withAnimation {
                    sourceLists[url] = sourceList
                }
            }

            let newMissingSourceLists = await SourceManager.shared.getMissingSourceLists()
            withAnimation {
                missingSourceLists = newMissingSourceLists
            }
        }
    }

    func listItem(name: String? = nil, url: URL, loading: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading) {
                if let name {
                    Text(name)
                }
                Text(url.absoluteString)
                    .lineLimit(1)
                    .font(.subheadline)
                    .foregroundStyle(name == nil ? .primary : .secondary)
            }
            if loading {
                ProgressView().progressViewStyle(.circular)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                sourceListsURLs.firstIndex(of: url).flatMap {
                    _ = sourceListsURLs.remove(at: $0)
                }
                sourceLists.removeValue(forKey: url)
                missingSourceLists.remove(url)
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
        let activeURLs = activeSourceListURLs
        let deleteURLs = offsets.map { activeURLs[$0] }
        Task {
            for url in deleteURLs {
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

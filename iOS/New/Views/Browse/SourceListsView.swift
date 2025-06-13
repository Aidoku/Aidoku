//
//  SourceListsView.swift
//  Aidoku
//
//  Created by Skitty on 6/5/25.
//

import SwiftUI

struct SourceListsView: View {
    @State private var sourceLists: [SourceList] = SourceManager.shared.sourceLists
    @State private var missingSourceLists: [URL] = []

    @State private var loading = false
    @State private var sourceListToAdd: String = ""
    @State private var showAddListAlert = false
    @State private var showAddListFailAlert = false

    var body: some View {
        List {
            ForEach(sourceLists, id: \.url) { sourceList in
                listItem(name: sourceList.name, url: sourceList.url)
            }
            .onDelete(perform: delete)

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
                    showAddListAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("SOURCE_LIST_ADD"), isPresented: $showAddListAlert) {
            TextField(NSLocalizedString("SOURCE_LIST_URL"), text: $sourceListToAdd)
                .keyboardType(.URL)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)

            Button(NSLocalizedString("CANCEL"), role: .cancel) {
                sourceListToAdd = ""
            }

            let is15Or16 = UIDevice.current.systemVersion.hasPrefix("15.") || UIDevice.current.systemVersion.hasPrefix("16.")
            Button(NSLocalizedString("OK")) {
                addSourceList(url: sourceListToAdd)
                sourceListToAdd = ""
            }
            .disabled(!is15Or16 && sourceListToAdd.isEmpty)
        } message: {
            Text(NSLocalizedString("SOURCE_LIST_ADD_TEXT"))
        }
        .alert(NSLocalizedString("SOURCE_LIST_ADD_FAIL"), isPresented: $showAddListFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("SOURCE_LIST_ADD_FAIL_TEXT"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateSourceLists)) { _ in
            withAnimation {
                loading = false
                sourceLists = SourceManager.shared.sourceLists
            }
        }
        .task {
            if SourceManager.shared.sourceLists.isEmpty {
                loading = true
                await SourceManager.shared.loadSourceLists()
                loading = false
            }
            if SourceManager.shared.sourceListURLs.count != sourceLists.count {
                missingSourceLists = SourceManager.shared.sourceListURLs.filter { url in
                    !sourceLists.contains(where: { $0.url == url })
                }
            }
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
                SourceManager.shared.removeSourceList(url: url)
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
        for url in urls {
            SourceManager.shared.removeSourceList(url: url)
        }
    }

    func addSourceList(url: String) {
        guard !url.isEmpty else { return }
        guard let url = URL(string: url) else {
            showAddListAlert = true
            return
        }
        Task {
            let success = await SourceManager.shared.addSourceList(url: url)
            if success {
                withAnimation {
                    sourceLists = SourceManager.shared.sourceLists
                    if SourceManager.shared.sourceListURLs.count != sourceLists.count {
                        missingSourceLists = SourceManager.shared.sourceListURLs.filter { url in
                            !sourceLists.contains(where: { $0.url == url })
                        }
                    }
                }
            } else {
                showAddListFailAlert = true
            }
        }
    }
}

#Preview {
    SourceListsView()
}

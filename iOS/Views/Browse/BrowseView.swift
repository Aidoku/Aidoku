//
//  BrowseView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/10/22.
//

import SwiftUI
import SwiftUIX

struct SourceSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .fontWeight(.medium)
            .padding(.horizontal)
            .padding(.top, 4)
    }
}

struct BrowseView: View {
    @State var sources = SourceManager.shared.sources
    
    @State var updates: [ExternalSourceInfo] = []
    @State var externalSources: [ExternalSourceInfo] = []
    
    @State var isEditing: Bool = false
    @State var isSearching: Bool = false
    @State var searchText: String = ""
    
    let sourcePublisher = NotificationCenter.default.publisher(for: NSNotification.Name("updateSourceList"))
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    if !updates.isEmpty && searchText.isEmpty {
                        SourceSectionHeader(title: "Updates")
                        ForEach(updates, id: \.self) { source in
                            ExternalSourceListCell(source: source, update: true)
                                .transition(.opacity)
                        }
                    }
                    if !sources.isEmpty {
                        SourceSectionHeader(title: "Installed")
                        ForEach(sources.filter { searchText.isEmpty ? true : $0.info.name.contains(searchText) }) { source in
                            NavigationLink {
                                SourceBrowseView(source: source)
                            } label: {
                                SourceListCell(source: source)
                                    .transition(.move(edge: .top))
                            }
                            .contextMenu {
                                Button {
                                    SourceManager.shared.remove(source: source)
                                    sources = SourceManager.shared.sources
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                            }
                        }
                    }
                    if let exSources = externalSources.filter { !SourceManager.shared.hasSourceInstalled(id: $0.id) }, !exSources.isEmpty {
                        SourceSectionHeader(title: "External")
                        ForEach(exSources.filter { searchText.isEmpty ? true : $0.name.contains(searchText) }, id: \.self) { source in
                            ExternalSourceListCell(source: source)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .navigationSearchBar {
                SearchBar("Search", text: $searchText, isEditing: $isEditing)
                    .showsCancelButton(isEditing)
            }
        }
        .onReceive(sourcePublisher) { _ in
            withAnimation {
                fetchUpdates()
                sources = SourceManager.shared.sources
            }
        }
        .onAppear {
            if externalSources.isEmpty {
                Task {
                    let result = (try? await URLSession.shared.object(from: URL(string: "https://skitty.xyz/aidoku-sources/index.json")!) as [ExternalSourceInfo]?) ?? []
                    withAnimation {
                        externalSources = result
                        fetchUpdates()
                    }
                }
            }
        }
    }
    
    func fetchUpdates() {
        updates = []
        for source in externalSources {
            if let installedSource = SourceManager.shared.source(for: source.id) {
                if source.version > installedSource.info.version {
                    updates.append(source)
                }
            }
        }
    }
}

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
    
    @State var isEditing: Bool = false
    @State var isSearching: Bool = false
    @State var searchText: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    SourceSectionHeader(title: "Installed")
                    ForEach(sources.filter { searchText.isEmpty ? true : $0.info.name.contains(searchText) }) { source in
                        NavigationLink {
                            Text("Coming Soon")
                                .foregroundColor(.secondary)
                                .navigationTitle(source.info.name)
                        } label: {
                            SourceListCell(source: source)
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
//                    SourceSectionHeader(title: "All")
//                    ForEach(sources) { source in
//                        ExternalSourceListCell(source: source)
//                            .id(UUID())
//                    }
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.large)
            .navigationSearchBar {
                SearchBar("Search", text: $searchText, isEditing: $isEditing)
                    .showsCancelButton(isEditing)
            }
        }
        .onAppear {
            sources = SourceManager.shared.sources
        }
    }
}

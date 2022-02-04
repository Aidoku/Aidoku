//
//  SearchView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/21.
//

import SwiftUI
import SwiftUIX

struct SearchView: View {
    
    @State var isEditing: Bool = false
    @State var searchText: String = ""
    
    var body: some View {
        NavigationView {
            Text("Under Construction")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .navigationSearchBar {
                SearchBar("Search", text: $searchText, isEditing: $isEditing)
                .showsCancelButton(isEditing)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

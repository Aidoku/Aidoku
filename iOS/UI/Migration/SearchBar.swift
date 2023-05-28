//
//  SearchBar.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/19/23.
//

import SwiftUI

public extension View {
    func navigationBarSearch(
        _ searchText: Binding<String>,
        searching: Binding<Bool>? = nil,
        hidesSearchBarWhenScrolling: Bool = true
    ) -> some View {
        overlay(SearchBar(
            text: searchText,
            searching: searching ?? Binding(get: { true }, set: { _, _ in }),
            hidesSearchBarWhenScrolling: hidesSearchBarWhenScrolling
        ).frame(width: 0, height: 0))
    }
}

private struct SearchBar: UIViewControllerRepresentable {

    let searchController = UISearchController(searchResultsController: nil)

    @Binding var text: String
    @Binding var searching: Bool

    let hidesSearchBarWhenScrolling: Bool

    func makeUIViewController(context: Context) -> SearchBarWrapperController {
        searchController.searchBar.delegate = context.coordinator
        searchController.searchResultsUpdater = context.coordinator

        searchController.hidesNavigationBarDuringPresentation = true
        searchController.obscuresBackgroundDuringPresentation = false

        return SearchBarWrapperController(searchController: searchController)
    }

    func updateUIViewController(_ controller: SearchBarWrapperController, context: Context) {
        controller.parent?.navigationItem.hidesSearchBarWhenScrolling = hidesSearchBarWhenScrolling
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UISearchBarDelegate, UISearchResultsUpdating {

        let parent: SearchBar

        init(_ parent: SearchBar) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.text = ""
        }

        func updateSearchResults(for searchController: UISearchController) {
            withAnimation {
                parent.searching = searchController.isActive
            }
        }
    }

    class SearchBarWrapperController: UIViewController {

        let searchController: UISearchController

        init(searchController: UISearchController) {
            self.searchController = searchController
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            self.parent?.navigationItem.searchController = searchController
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            self.parent?.navigationItem.searchController = searchController
        }
    }
}

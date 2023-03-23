//
//  SearchBar.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/19/23.
//

import SwiftUI
import Combine

public extension View {
    func navigationBarSearch(
        _ searchText: Binding<String>,
        searching: Binding<Bool>? = nil,
        hidesSearchBarWhenScrolling: Bool = true
    ) -> some View {
        overlay(SearchBar(
            text: searchText,
            searching: searching,
            hidesSearchBarWhenScrolling: hidesSearchBarWhenScrolling
        ).frame(width: 0, height: 0))
    }
}

private struct SearchBar: UIViewControllerRepresentable {

    @Binding var text: String
    @Binding var searching: Bool

    let hidesSearchBarWhenScrolling: Bool

    init(text: Binding<String>, searching: Binding<Bool>?, hidesSearchBarWhenScrolling: Bool = true) {
        self._text = text
        self._searching = searching ?? Binding(get: { true }, set: { _, _ in })
        self.hidesSearchBarWhenScrolling = hidesSearchBarWhenScrolling
    }

    func makeUIViewController(context: Context) -> SearchBarWrapperController {
        SearchBarWrapperController()
    }

    func updateUIViewController(_ controller: SearchBarWrapperController, context: Context) {
        controller.searchController = context.coordinator.searchController
        controller.parent?.navigationItem.hidesSearchBarWhenScrolling = hidesSearchBarWhenScrolling
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, searching: $searching)
    }

    class Coordinator: NSObject, UISearchResultsUpdating {

        @Binding var text: String
        @Binding var searching: Bool
        let searchController: UISearchController

        private var subscription: AnyCancellable?

        init(text: Binding<String>, searching: Binding<Bool>) {
            self._text = text
            self._searching = searching
            self.searchController = UISearchController(searchResultsController: nil)

            super.init()

            searchController.searchResultsUpdater = self
            searchController.hidesNavigationBarDuringPresentation = true
            searchController.obscuresBackgroundDuringPresentation = false

            self.searchController.searchBar.text = self.text
            self.subscription = self.text.publisher.sink { _ in
                self.searchController.searchBar.text = self.text
            }
        }

        deinit {
            self.subscription?.cancel()
        }

        func updateSearchResults(for searchController: UISearchController) {
            guard let text = searchController.searchBar.text else { return }
            self.text = text
            withAnimation {
                self.searching = searchController.isActive
            }
        }
    }

    class SearchBarWrapperController: UIViewController {

        var searchController: UISearchController? {
            didSet {
                self.parent?.navigationItem.searchController = searchController
            }
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

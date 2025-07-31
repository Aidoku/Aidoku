//
//  CustomSearchable.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import SwiftUI

extension View {
    func customSearchable(
        text: Binding<String>,
        enabled: Binding<Bool> = .constant(true),
        focused: Binding<Bool?> = .constant(nil),
        hideCancelButton: Bool = false,
        hidesNavigationBarDuringPresentation: Bool = true,
        hidesSearchBarWhenScrolling: Bool = true,
        bookmarkIcon: UIImage? = nil,
        onSubmit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onBookmarkPress: (() -> Void)? = nil,
    ) -> some View {
        overlay(
            CustomSearchBar(
                searchText: text,
                enabled: enabled,
                focused: focused,
                hideCancelButton: hideCancelButton,
                hidesNavigationBarDuringPresentation: hidesNavigationBarDuringPresentation,
                hidesSearchBarWhenScrolling: hidesSearchBarWhenScrolling,
                bookmarkIcon: bookmarkIcon,
                onSubmit: onSubmit,
                onCancel: onCancel,
                onBookmarkPress: onBookmarkPress
            )
            .frame(width: 0, height: 0)
        )
    }
}

private struct CustomSearchBar: UIViewControllerRepresentable {
    var searchController: UISearchController = .init(searchResultsController: nil)

    @Environment(\.autocorrectionDisabled) var autocorrectionDisabled

    @Binding var searchText: String
    @Binding var enabled: Bool
    @Binding var focused: Bool?
    let hideCancelButton: Bool
    let hidesNavigationBarDuringPresentation: Bool
    let hidesSearchBarWhenScrolling: Bool
    let bookmarkIcon: UIImage?
    let onSubmit: (() -> Void)?
    let onCancel: (() -> Void)?
    let onBookmarkPress: (() -> Void)?

    class Coordinator: NSObject, UISearchBarDelegate, UISearchResultsUpdating {
        let parent: CustomSearchBar

        init(_ parent: CustomSearchBar) {
            self.parent = parent
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.searchText = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            if let onSubmit = parent.onSubmit {
                onSubmit()
            }
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            parent.searchText = ""
            if let onCancel = parent.onCancel {
                onCancel()
            }
        }

        func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
            if let onBookmarkPress = parent.onBookmarkPress {
                onBookmarkPress()
            }
        }

        func updateSearchResults(for searchController: UISearchController) {
            if parent.focused != nil && parent.focused != searchController.isActive {
                parent.focused = searchController.isActive
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> NavSearchBarWrapper {
        searchController.hidesNavigationBarDuringPresentation = true
        searchController.searchBar.delegate = context.coordinator
        searchController.searchResultsUpdater = context.coordinator
        searchController.searchBar.autocorrectionType = autocorrectionDisabled ? .no : .yes
        searchController.navigationItem.hidesSearchBarWhenScrolling = hidesSearchBarWhenScrolling
        if let bookmarkIcon {
            searchController.searchBar.showsBookmarkButton = true
            searchController.searchBar.setImage(bookmarkIcon, for: .bookmark, state: .normal)
        }

        return NavSearchBarWrapper(searchController: searchController, hidesSearchBarWhenScrolling: hidesSearchBarWhenScrolling)
    }

    func updateUIViewController(_ controller: NavSearchBarWrapper, context: Context) {
        controller.searchController.searchBar.text = searchText
        controller.searchController.searchBar.autocorrectionType = autocorrectionDisabled ? .no : .yes
        if controller.shouldShow != enabled {
            controller.setShow(enabled)
        }
        if hideCancelButton {
            controller.searchController.searchBar.showsCancelButton = false
        }
        controller.searchController.hidesNavigationBarDuringPresentation = hidesNavigationBarDuringPresentation
        if let focused {
            // putting this in a task slightly delays it, allowing the search bar to show before we focus it
            Task {
                if focused {
                    if !controller.searchController.isActive {
                        controller.searchController.isActive = true
                        controller.searchController.searchBar.becomeFirstResponder()
                        controller.parent?.navigationItem.searchController?.isActive = true
                        controller.parent?.navigationItem.searchController?.searchBar.becomeFirstResponder()
                    }
                } else {
                    if controller.searchController.isActive {
                        controller.searchController.isActive = false
                    }
                }
            }
        }
    }

    class NavSearchBarWrapper: UIViewController {
        var searchController: UISearchController
        let hidesSearchBarWhenScrolling: Bool
        var shouldShow = false

        init(searchController: UISearchController, hidesSearchBarWhenScrolling: Bool) {
            self.searchController = searchController
            self.hidesSearchBarWhenScrolling = hidesSearchBarWhenScrolling
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if shouldShow {
                show()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if shouldShow {
                show()
            }
        }

        func setShow(_ show: Bool) {
            shouldShow = show
            if show {
                self.show()
            } else {
                hide()
            }
        }

        func show() {
            parent?.navigationItem.searchController = searchController
            parent?.navigationItem.hidesSearchBarWhenScrolling = hidesSearchBarWhenScrolling
            if #available(iOS 16.0, *) {
                parent?.navigationItem.preferredSearchBarPlacement = .stacked
            }

            // fix large navbar not displaying fully
            parent?.navigationController?.navigationBar.sizeToFit()
        }

        func hide() {
            parent?.navigationItem.searchController = nil
        }
    }
}

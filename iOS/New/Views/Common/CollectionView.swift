//
//  CollectionView.swift
//  Aidoku
//
//  Created by Skitty on 1/1/25.
//

import SwiftUI

struct CollectionViewSection {
    let items: [AnyView]
}

struct CollectionView: UIViewControllerRepresentable {
    let sections: [CollectionViewSection]
    let layout: UICollectionViewCompositionalLayout
    let collectionViewController: UICollectionViewController

    init(sections: [CollectionViewSection], layout: UICollectionViewCompositionalLayout) {
        self.sections = sections
        self.layout = layout
        self.collectionViewController = UICollectionViewController(collectionViewLayout: layout)
    }

    func makeUIViewController(context: Context) -> UICollectionViewController {
        collectionViewController.collectionView.isScrollEnabled = false
        collectionViewController.collectionView.dataSource = context.coordinator
        collectionViewController.collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "Cell")
        return collectionViewController
    }

    func updateUIViewController(_ uiViewController: UICollectionViewController, context: Context) {
        uiViewController.collectionView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UICollectionViewDataSource {
        var parent: CollectionView

        init(_ parent: CollectionView) {
            self.parent = parent
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
           parent.sections.count
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.sections[section].items.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath)
            let hostingController = UIHostingController(
                rootView: parent.sections[indexPath.section].items[indexPath.item],
                // there's a bug on ios <=16 where the views will shift down after you scroll down
                ignoreSafeArea: true
            )
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            parent.collectionViewController.addChild(hostingController)
            cell.contentView.addSubview(hostingController.view)
            hostingController.didMove(toParent: parent.collectionViewController)

            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                hostingController.view.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor)
            ])

            return cell
        }
    }
}

// MARK: - Layouts

typealias GetSection = (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection

extension CollectionView {
    static func mangaListLayout(
        itemsPerPage: Int,
        totalItems: Int
    ) -> (GetSection, CGFloat) {
        let itemHeight: CGFloat = 100
        let spacing: CGFloat = 10

        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        ))

        let itemsPerPage = min(itemsPerPage, totalItems)
        let viewHeight = CGFloat(itemsPerPage) * itemHeight + CGFloat(itemsPerPage - 1) * spacing

        let getSection: (NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection = { environment in
            let columnsToFit = floor(environment.container.effectiveContentSize.width / 340)

            let regularGroup = NSCollectionLayoutGroup.vertical(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(0.9 / max(1, columnsToFit)),
                    heightDimension: .absolute(viewHeight)
                ),
                subitem: item,
                count: itemsPerPage
            )
            regularGroup.interItemSpacing = .fixed(spacing)
            regularGroup.edgeSpacing = .init(leading: .none, top: .none, trailing: .none, bottom: .none)

            let section = NSCollectionLayoutSection(group: regularGroup)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 40)
            section.orthogonalScrollingBehavior = totalItems > itemsPerPage ? .groupPaging : .none // disable paging if there are not enough items

            return section
        }

        return (getSection, viewHeight)
    }
}

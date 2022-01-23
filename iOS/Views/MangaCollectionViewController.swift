//
//  MangaCollectionViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class MangaCollectionViewController: UIViewController {
    
    var collectionView: UICollectionView?
    var manga: [Manga] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: MangaGridFlowLayout(
            cellsPerRow: 2,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: view.layoutMargins
        ))
        collectionView?.delegate = self
        collectionView?.dataSource = self
        collectionView?.delaysContentTouches = false
        collectionView?.register(MangaCoverCell.self, forCellWithReuseIdentifier: "MangaCoverCell")
        collectionView?.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView ?? UICollectionView())
        
        collectionView?.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        collectionView?.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
    }
    
    override func viewLayoutMarginsDidChange() {
        if let layout = collectionView?.collectionViewLayout as? MangaGridFlowLayout {
            layout.sectionInset = UIEdgeInsets(top: 0, left: view.layoutMargins.left, bottom: 10, right: view.layoutMargins.right)
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        let cellsPerRow = size.width > size.height ? 5 : 2
        
        collectionView?.collectionViewLayout = MangaGridFlowLayout(
            cellsPerRow: cellsPerRow,
            minimumInteritemSpacing: 12,
            minimumLineSpacing: 12,
            sectionInset: view.layoutMargins
        )
    }
    
    func reloadData() {
        collectionView?.performBatchUpdates {
            self.collectionView?.reloadSections(IndexSet(integer: 0))
        }
    }
}

// MARK: - Collection View Data Source
extension MangaCollectionViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        manga.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        var cell = collectionView.dequeueReusableCell(withReuseIdentifier: "MangaCoverCell", for: indexPath) as? MangaCoverCell
        if cell == nil {
            cell = MangaCoverCell(frame: .zero)
        }
        cell?.manga = manga[indexPath.row]
        return cell ?? UICollectionViewCell()
    }
}

// MARK: - Collection View Delegate
extension MangaCollectionViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vc = HostingController(rootView: MangaView(manga: manga[indexPath.row]))
        vc.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaCoverCell {
            cell.highlight()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? MangaCoverCell {
            cell.unhighlight(animated: true)
        }
    }
}

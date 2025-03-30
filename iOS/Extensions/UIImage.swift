//
//  UIImage.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/13/22.
//

import UIKit
import Photos

extension UIImage {
    func sizeToFit(_ pageSize: CGSize) -> CGSize {
        guard size.height * size.width * pageSize.width * pageSize.height > 0 else { return .zero }

        let scaledHeight = size.height * (pageSize.width / size.width)
        return CGSize(width: pageSize.width, height: scaledHeight)
    }

    func saveToAlbum(_ name: String? = nil) {
        let albumName = name ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Aidoku"
        guard let album = fetchAlbum(albumName) else {
            UIImageWriteToSavedPhotosAlbum(self, nil, nil, nil)
            return
        }

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: self)
            guard let placeholder = request.placeholderForCreatedAsset else { return }
            guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            albumChangeRequest.addAssets([placeholder] as NSFastEnumeration)
        }
    }

    private func fetchAlbum(_ name: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title == %@", name)
        if let album = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject {
            return album
        }

        var placeholder: PHObjectPlaceholder?
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
                placeholder = request.placeholderForCreatedAssetCollection
            }
        } catch { return nil }
        guard let album = placeholder else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.localIdentifier], options: nil).firstObject
    }
}

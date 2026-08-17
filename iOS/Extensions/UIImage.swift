//
//  UIImage.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/13/22.
//

import Photos
import UIKit

extension UIImage {
    @MainActor
    func saveToAlbum(_ name: String? = nil, viewController: UIViewController) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status != .restricted && status != .denied else {
            let alertController = confirmAction(
                title: NSLocalizedString("ENABLE_PERMISSION"),
                message: NSLocalizedString("PHOTOS_ACCESS_DENIED_TEXT"),
                continueActionName: NSLocalizedString("SETTINGS")
            ) {
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settings)
                }
            }
            viewController.present(alertController, animated: true)
            return
        }

        let albumName =
            name ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "Aidoku"
        func fallback() {
            UIImageWriteToSavedPhotosAlbum(self, nil, nil, nil)
            LogManager.logger.error("Failed to save image to album: \(albumName)")
        }
        guard let album = fetchAlbum(albumName) else {
            fallback()
            return
        }

        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest.creationRequestForAsset(from: self)
            guard
                let placeholder = request.placeholderForCreatedAsset,
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
            else {
                fallback()
                return
            }
            albumChangeRequest.addAssets([placeholder] as NSFastEnumeration)
        }
    }
}

@MainActor
private func confirmAction(
    title: String? = nil,
    message: String? = nil,
    actions: [UIAlertAction] = [],
    continueActionName: String = NSLocalizedString("CONTINUE"),
    destructive: Bool = true,
    proceed: @escaping () -> Void
) -> UIAlertController {
    let alertView = UIAlertController(
        title: title,
        message: message,
        preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet
    )

    for action in actions {
        alertView.addAction(action)
    }
    let action = UIAlertAction(
        title: continueActionName,
        style: destructive ? .destructive : .default
    ) { _ in
        proceed()
    }
    alertView.addAction(action)

    alertView.addAction(UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel))

    return alertView
}

private func fetchAlbum(_ name: String) -> PHAssetCollection? {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "title == %@", name)
    if let album = PHAssetCollection.fetchAssetCollections(
        with: .album, subtype: .any, options: options
    ).firstObject {
        return album
    }

    var placeholder: PHObjectPlaceholder?
    do {
        try PHPhotoLibrary.shared().performChangesAndWait {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }
    } catch { return nil }
    guard let album = placeholder else { return nil }
    return PHAssetCollection.fetchAssetCollections(
        withLocalIdentifiers: [album.localIdentifier], options: nil
    ).firstObject
}

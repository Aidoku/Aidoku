//
//  DocumentPickerView.swift
//  Aidoku
//
//  Created by Skitty on 7/1/25.
//  Modified from https://github.com/khcrysalis/Feather/blob/main/NimbleKit/Sources/NimbleViews/UIKit/FileImporterRepresentableView.swift
//

import SwiftUI
import UniformTypeIdentifiers

// necessary to prevent coordinator from getting dropped on macOS
private final class CoordinatedDocumentPickerViewController: UIDocumentPickerViewController {
    var coordinator: DocumentPickerView.Coordinator?

    override var delegate: (any UIDocumentPickerDelegate)? {
        get { coordinator }
        set {}
    }
}

public struct DocumentPickerView: UIViewControllerRepresentable {
    public var allowedContentTypes: [UTType]
    public var allowsMultipleSelection: Bool = false
    public var onDocumentsPicked: ([URL]) -> Void

    public init(
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onDocumentsPicked: @escaping ([URL]) -> Void
    ) {
        self.allowedContentTypes = allowedContentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onDocumentsPicked = onDocumentsPicked
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // setting asCopy to true fixes issues when sideloading the app
        let picker = CoordinatedDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.coordinator = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.allowsMultipleSelection = allowsMultipleSelection
        (uiViewController as? CoordinatedDocumentPickerViewController)?.coordinator = context.coordinator
    }

    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerView

        init(parent: DocumentPickerView) {
            self.parent = parent
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onDocumentsPicked(urls)
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onDocumentsPicked([])
        }
    }
}

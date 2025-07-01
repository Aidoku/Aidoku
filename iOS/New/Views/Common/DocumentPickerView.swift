//
//  DocumentPickerView.swift
//  Aidoku
//
//  Created by Skitty on 7/1/25.
//  Modified from https://github.com/khcrysalis/Feather/blob/main/NimbleKit/Sources/NimbleViews/UIKit/FileImporterRepresentableView.swift
//

import SwiftUI
import UniformTypeIdentifiers

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
        Coordinator(onDocumentsPicked: onDocumentsPicked)
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // setting asCopy to true fixes issues when sideloading the app
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onDocumentsPicked: ([URL]) -> Void

        init(onDocumentsPicked: @escaping ([URL]) -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDocumentsPicked(urls)
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onDocumentsPicked([])
        }
    }
}

//
//  SafariView.swift
//  Aidoku
//
//  Created by skitty on 5/17/26.
//

import SafariServices
import SwiftUI

struct SafariView: UIViewControllerRepresentable {
    @Binding var url: URL?

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let url = if let url, url.scheme == "http" || url.scheme == "https" {
            url
        } else {
            URL(string: "https://aidoku.app")!
        }
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

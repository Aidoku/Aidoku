//
//  MarkdownView.swift
//  Aidoku
//
//  Created by Skitty on 5/20/25.
//

import MarkdownUI
import SwiftUI

struct MarkdownView: View {
    @State private var markdownString: String
    @State private var safariUrl: URL?
    @State private var showSafari = false

    init(_ markdownString: String) {
        self.markdownString = markdownString
    }

    var body: some View {
        Markdown {
            markdownString
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.scheme == "http" || url.scheme == "https" {
                    safariUrl = url
                    showSafari = true
                }
                return .handled
            }
        )
        .padding()
        .fullScreenCover(isPresented: $showSafari) {
            SafariView(url: $safariUrl)
                .ignoresSafeArea()
        }
    }
}

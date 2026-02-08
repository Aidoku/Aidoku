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
    
    let fontFamily: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat

    init(_ markdownString: String, fontFamily: String = "Georgia", fontSize: CGFloat = 18, lineSpacing: CGFloat = 8) {
        self.markdownString = markdownString
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
    }
    
    private var textFont: Font {
        if fontFamily == "System" {
            return .system(size: fontSize)
        }
        return .custom(fontFamily, size: fontSize)
    }

    var body: some View {
        Markdown {
            markdownString
        }
        .markdownTextStyle {
            FontFamily(.custom(fontFamily == "System" ? ".AppleSystemUIFont" : fontFamily))
            FontSize(fontSize)
        }
        .markdownBlockStyle(\.paragraph) { configuration in
            configuration.label
                .lineSpacing(lineSpacing)
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

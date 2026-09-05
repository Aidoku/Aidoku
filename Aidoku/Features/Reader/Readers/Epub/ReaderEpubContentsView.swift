//
//  ReaderEpubContentsView.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/18/26.
//

import SwiftUI

// the sibling of ReaderChapterListView, which moves between books where this moves within one
struct ReaderEpubContentsView: View {
    let contents: EpubTableOfContents
    // resolved when the list appears, only the layout being able to answer it
    let currentEntry: () async -> EpubTableOfContents.Entry?
    let bookPage: (EpubTableOfContents.Entry) -> Int?
    var entrySet: ((EpubTableOfContents.Entry) -> Void)?

    @State private var current: EpubTableOfContents.Entry?

    @Environment(\.dismiss) private var dismiss

    private var entryList: some View {
        ScrollViewReader { proxy in
            List(contents.entries) { entry in
                Button {
                    entrySet?(entry)
                } label: {
                    row(for: entry)
                }
                .id(entry.id)
            }
            .task {
                let current = await currentEntry()
                self.current = current
                if let current {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }

    // deep contents exist, and indenting every level leaves no width for the title
    private static let indent: CGFloat = 16
    private static let maximumIndentedDepth = 4

    var body: some View {
        PlatformNavigationStack {
            Group {
                if contents.isEmpty {
                    // A book is free to declare no contents, and plenty do. Saying so is better
                    // than the alternatives: an empty list reads as a list that failed to load,
                    // and a button that never becomes usable reads as a broken button.
                    UnavailableView(
                        NSLocalizedString("NO_CONTENTS"),
                        systemImage: "list.bullet.indent",
                        description: Text(NSLocalizedString("NO_CONTENTS_TEXT"))
                    )
                } else {
                    entryList
                }
            }
            .navigationTitle(NSLocalizedString("CONTENTS", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
        }
    }

    private func row(for entry: EpubTableOfContents.Entry) -> some View {
        let page = bookPage(entry)
        let indent = CGFloat(min(entry.depth, Self.maximumIndentedDepth)) * Self.indent
        return HStack(alignment: .firstTextBaseline) {
            Text(entry.title)
                .font(.subheadline)
                .foregroundColor(entry == current ? .accentColor : .primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let page {
                Text(String(page))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, indent)
    }
}

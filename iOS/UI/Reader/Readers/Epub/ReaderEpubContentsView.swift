//
//  ReaderEpubContentsView.swift
//  Aidoku (iOS)
//
//  Created by Pietro Baiguini on 8/18/26.
//

import SwiftUI

/// The table of contents of the open book, as the reader's contents button presents it.
///
/// The sibling of `ReaderChapterListView`, and deliberately shaped like it: a list that opens on
/// where the reader is and takes them somewhere when tapped. What differs is what the list holds.
/// The chapter list moves between the books of a series, since one ePub is one chapter; this moves
/// within the book that is open, which is otherwise reachable only by dragging the slider.
struct ReaderEpubContentsView: View {
    let contents: EpubTableOfContents
    /// Resolved when the list appears rather than passed in, because a book whose contents are
    /// finer than its spine can only say which entry the reader is inside once the document they
    /// are in has been laid out.
    let currentEntry: () async -> EpubTableOfContents.Entry?
    /// The book page an entry begins at, nil while the pages before it are still being counted.
    let bookPage: (EpubTableOfContents.Entry) -> Int?
    var entrySet: ((EpubTableOfContents.Entry) -> Void)?

    @State private var current: EpubTableOfContents.Entry?

    @Environment(\.dismiss) private var dismiss

    /// How far a level of nesting indents a row, and how many levels are indented at all.
    ///
    /// Deep contents exist: a technical book nests four or five levels, and indenting every one of
    /// them would leave the deepest rows with no width for their own titles.
    private static let indent: CGFloat = 16
    private static let maximumIndentedDepth = 4

    var body: some View {
        PlatformNavigationStack {
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

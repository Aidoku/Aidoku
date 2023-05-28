//
//  ReaderChapterListView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/20/22.
//

import SwiftUI

// UIKit close button for SwiftUI
private struct CloseButton: UIViewRepresentable {
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func makeUIView(context: Context) -> UIButton {
        UIButton(type: .close, primaryAction: UIAction { _ in action() })
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

struct ReaderChapterListView: View {
    @Environment(\.presentationMode) var presentationMode

    var chapterList: [Chapter]
    @State var chapter: Chapter
    var chapterSet: ((Chapter) -> Void)?

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List(chapterList) { chapter in
                    Button {
                        self.chapter = chapter
                        chapterSet?(chapter)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(displayString(for: chapter))
                                    .foregroundColor(.primary)
                                    .font(.subheadline)
                                if let title = chapter.title {
                                    Text(title)
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                            Spacer()
                            if chapter == self.chapter {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .id(chapter.id)
                }
                .onAppear {
                    proxy.scrollTo(chapter.id, anchor: .center)
                }
            }
            .navigationTitle(NSLocalizedString("CHAPTERS", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    CloseButton {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    func displayString(for chapter: Chapter) -> String {
        let str: String

        if let chapterNum = chapter.chapterNum {
            if let volumeNum = chapter.volumeNum {
                str = String(
                    format: NSLocalizedString("VOL_X", comment: "") + " " + NSLocalizedString("CH_X", comment: ""),
                    volumeNum,
                    chapterNum
                )
            } else {
                str = String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
            }
        } else if let volumeNum = chapter.volumeNum {
            str = String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNum)
        } else {
            str = ""
        }

        return str
    }
}

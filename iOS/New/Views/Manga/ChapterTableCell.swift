//
//  ChapterTableCell.swift
//  Aidoku
//
//  Created by Skitty on 8/17/23.
//

import AidokuRunner
import SwiftUI

struct ChapterTableCell: View {
    let source: AidokuRunner.Source?
    let sourceKey: String
    let chapter: AidokuRunner.Chapter
    let read: Bool
    let page: Int?
    let downloaded: Bool
    var downloadProgress: Float?
    let displayMode: ChapterTitleDisplayMode

    var locked: Bool {
        chapter.locked && !downloaded
    }

    var body: some View {
        HStack {
            if let thumbnail = chapter.thumbnail {
                MangaCoverView(
                    source: source,
                    coverImage: thumbnail,
                    width: 40,
                    height: 40
                )
            }

            VStack(alignment: .leading, spacing: 8 / 3) {
                let title = chapter.formattedTitle(forceMode: displayMode)
                Text(title)
                    .foregroundStyle(locked || read ? .secondary : .primary)
                    .font(.system(size: 16))
                    .lineLimit(1)
                if let subtitle = chapter.formattedSubtitle(page: page, sourceKey: sourceKey) {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
            } else if let downloadProgress {
                DownloadProgressView(progress: downloadProgress)
                    .frame(width: 13, height: 13)
            } else if locked {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.vertical, 22 / 3)
        .frame(alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct DownloadProgressView: UIViewRepresentable {
    var progress: Float

    func makeUIView(context: Context) -> CircularProgressView {
        let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 13, height: 13))
        progressView.radius = 13 / 2
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = progressView.tintColor
        return progressView
    }

    func updateUIView(_ uiView: CircularProgressView, context: Context) {
        uiView.setProgress(value: progress, withAnimation: false)
    }
}

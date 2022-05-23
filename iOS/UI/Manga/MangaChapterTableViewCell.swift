//
//  MangaChapterTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/16/22.
//

import UIKit

class MangaChapterTableViewCell: UITableViewCell {

    let chapter: Chapter
    var read: Bool

    lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView(frame: CGRect(x: 1, y: 1, width: 13, height: 13))
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = tintColor
        return progressView
    }()

    lazy var downloadedView: UIImageView = {
        let downloadedView = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
        downloadedView.frame = CGRect(x: 0, y: 0, width: 15, height: 15)
        downloadedView.tintColor = .tertiaryLabel
        return downloadedView
    }()

    lazy var downloadWrapperView: UIView = {
        let view = UIView()
        view.frame = CGRect(x: 0, y: 0, width: 15, height: 15)
        return view
    }()

    init(chapter: Chapter, read: Bool = false, reuseIdentifier: String? = nil) {
        self.chapter = chapter
        self.read = read
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        loadLabels()
        checkDownloaded()

        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadProgressed"), object: nil, queue: nil) { notification in
            if let download = notification.object as? Download,
               download.chapterId == chapter.id {
                Task { @MainActor in
                    self.accessoryView?.isHidden = false
                    self.progressView.setProgress(value: Float(download.progress) / Float(download.total), withAnimation: false)
                }
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadFinished"), object: nil, queue: nil) { notification in
            if let download = notification.object as? Download,
               download.chapterId == chapter.id {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadRemoved"), object: nil, queue: nil) { notification in
            if let download = notification.object as? Chapter,
               download.id == chapter.id {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadCancelled"), object: nil, queue: nil) { notification in
            if let download = notification.object as? Chapter,
               download.id == chapter.id {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("downloadQueued"), object: nil, queue: nil) { notification in
            if let download = notification.object as? Download,
               download.chapterId == chapter.id {
                Task { @MainActor in
                    self.accessoryView?.isHidden = false
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func loadLabels() {
        // title string
        // Vol.X Ch.X - Title
        var titleString = ""
        if chapter.volumeNum == nil && chapter.title == nil, let chapterNum = chapter.chapterNum {
            titleString = String(format: "Chapter %g", chapterNum)
        } else {
            if let volumeNum = chapter.volumeNum {
                titleString.append(String(format: "Vol.%g ", volumeNum))
            }
            if let chapterNum = chapter.chapterNum {
                titleString.append(String(format: "Ch.%g ", chapterNum))
            }
            if (chapter.volumeNum != nil || chapter.chapterNum != nil) && chapter.title != nil {
                titleString.append("- ")
            }
            if let title = chapter.title {
                titleString.append(title)
            } else if chapter.chapterNum == nil {
                titleString = NSLocalizedString("UNTITLED", comment: "")
            }
        }
        textLabel?.text = titleString

        // subtitle string
        // date • scanlator • language
        var subtitleString = ""
        if let dateUploaded = chapter.dateUploaded {
            subtitleString.append(DateFormatter.localizedString(from: dateUploaded, dateStyle: .medium, timeStyle: .none))
        }
        if chapter.dateUploaded != nil && chapter.scanlator != nil {
            subtitleString.append(" • ")
        }
        if let scanlator = chapter.scanlator {
            subtitleString.append(scanlator)
        }
        if UserDefaults.standard.array(forKey: "\(chapter.sourceId).languages")?.count ?? 0 > 1 {
            subtitleString.append(" • \(chapter.lang)")
        }
        detailTextLabel?.text = subtitleString

        if read {
            textLabel?.textColor = .secondaryLabel
        } else {
            textLabel?.textColor = .label
        }

        textLabel?.font = .systemFont(ofSize: 15)
        detailTextLabel?.font = .systemFont(ofSize: 14)
        detailTextLabel?.textColor = .secondaryLabel
        accessoryView?.bounds = CGRect(x: 0, y: 0, width: 15, height: 15)
        backgroundColor = .clear

        accessoryView = downloadWrapperView
        downloadWrapperView.addSubview(progressView)
        downloadWrapperView.addSubview(downloadedView)
    }

    func checkDownloaded() {
        let downloadStatus = DownloadManager.shared.getDownloadStatus(for: chapter)
        if downloadStatus == .finished {
            progressView.isHidden = true
            downloadedView.isHidden = false
            progressView.progress = 0
            accessoryView?.isHidden = false
        } else {
            downloadedView.isHidden = true
            progressView.progress = 0
            progressView.isHidden = false
            accessoryView?.isHidden = downloadStatus == .none
        }
    }
}

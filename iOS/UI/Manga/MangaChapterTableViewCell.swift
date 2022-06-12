//
//  MangaChapterTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/16/22.
//

import UIKit

class MangaChapterTableViewCell: UITableViewCell {

    let chapter: Chapter
    var completed: Bool
    var page: Int = 0

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

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    init(chapter: Chapter, completed: Bool = false, page: Int = 0, reuseIdentifier: String? = nil) {
        self.chapter = chapter
        self.completed = completed
        self.page = page
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        loadLabels()
        checkDownloaded()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadProgressed"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let download = notification.object as? Download,
               download.chapterId == chapter.id {
                Task { @MainActor in
                    self.accessoryView?.isHidden = false
                    self.progressView.setProgress(value: Float(download.progress) / Float(download.total), withAnimation: false)
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadFinished"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let download = notification.object as? Download,
               download.chapterId == chapter.id {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadRemoved"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let download = notification.object as? Chapter,
               download.id == chapter.id {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadsRemoved"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let download = notification.object as? Manga,
               download.id == chapter.mangaId {
                 Task { @MainActor in
                     self.checkDownloaded()
                 }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadCancelled"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let download = notification.object as? Chapter,
               download.id == chapter.id {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadsCancelled"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let downloads = notification.object as? [Chapter],
               downloads.contains(chapter) {
                Task { @MainActor in
                    self.checkDownloaded()
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name("downloadsQueued"), object: nil, queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            if let downloads = notification.object as? [Download] {
                for download in downloads where download.chapterId == chapter.id {
                    Task { @MainActor in
                        self.accessoryView?.isHidden = false
                    }
                    break
                }
            }
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // swiftlint:disable:next cyclomatic_complexity
    func loadLabels() {
        // title string
        // Vol.X Ch.X - Title
        var titleString = ""
        if chapter.volumeNum == nil && chapter.title == nil, let chapterNum = chapter.chapterNum {
            titleString = String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
        } else {
            if let volumeNum = chapter.volumeNum {
                titleString.append(String(format: "\(NSLocalizedString("VOL_X", comment: "")) ", volumeNum))
            }
            if let chapterNum = chapter.chapterNum {
                titleString.append(String(format: "\(NSLocalizedString("CH_X", comment: "")) ", chapterNum))
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
        // date • page • scanlator • language
        var subtitleString = ""
        if let dateUploaded = chapter.dateUploaded {
            subtitleString.append(DateFormatter.localizedString(from: dateUploaded, dateStyle: .medium, timeStyle: .none))
        }
        if page > 0 {
            if !subtitleString.isEmpty {
                subtitleString.append(" • ")
            }
            subtitleString.append(String(format: NSLocalizedString("PAGE_X", comment: ""), page))
        }
        if (chapter.dateUploaded != nil || page > 0) && chapter.scanlator != nil {
            subtitleString.append(" • ")
        }
        if let scanlator = chapter.scanlator {
            subtitleString.append(scanlator)
        }
        if UserDefaults.standard.array(forKey: "\(chapter.sourceId).languages")?.count ?? 0 > 1 {
            subtitleString.append(" • \(chapter.lang)")
        }
        detailTextLabel?.text = subtitleString

        if completed {
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

//
//  ChapterCellConfiguration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import UIKit

struct ChapterCellConfiguration: UIContentConfiguration {

    var chapter: Chapter
    var currentPage: Int?
    var read = false
    var downloaded = false
    var downloading = false
    var downloadProgress: Float = 0

    func makeContentView() -> UIView & UIContentView {
        ChapterCellContentView(self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

class ChapterCellContentView: UIView, UIContentView {

    var configuration: UIContentConfiguration {
        didSet {
            configure()
        }
    }

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }()

    private lazy var subtitleLabel: UILabel = {
        let subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        return subtitleLabel
    }()

    private let accessoryView = UIView()

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView(frame: CGRect(x: 1, y: 1, width: 13, height: 13))
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = tintColor
        progressView.isHidden = true
        return progressView
    }()

    private lazy var downloadedView: UIImageView = {
        let downloadedView = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
        downloadedView.frame = CGRect(x: 0, y: 0, width: 15, height: 15)
        downloadedView.tintColor = .tertiaryLabel
        return downloadedView
    }()

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        accessoryView.addSubview(progressView)
        accessoryView.addSubview(downloadedView)
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accessoryView)

        constrain()
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func constrain() {
        NSLayoutConstraint.activate([
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22/3),
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor, constant: -12),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8/3),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22/3),
            subtitleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor, constant: -12),

            accessoryView.widthAnchor.constraint(equalToConstant: 15),
            accessoryView.heightAnchor.constraint(equalToConstant: 15),
            accessoryView.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor, constant: -12),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
    }

    func configure() {
        guard let configuration = configuration as? ChapterCellConfiguration else { return }
        titleLabel.text = makeTitle(chapter: configuration.chapter)
        titleLabel.textColor = configuration.read ? .secondaryLabel : .label
        subtitleLabel.text = makeSubtitle(chapter: configuration.chapter, page: configuration.currentPage)
        subtitleLabel.isHidden = subtitleLabel.text == nil
        downloadedView.isHidden = !configuration.downloaded
        progressView.isHidden = !configuration.downloading
        progressView.setProgress(value: configuration.downloadProgress, withAnimation: false)
    }

    /// Returns a formatted title for provided chapter.
    /// `Vol.X Ch.X - Title`
    private func makeTitle(chapter: Chapter) -> String {
        if chapter.volumeNum == nil && chapter.title == nil, let chapterNum = chapter.chapterNum {
            // Chapter X
            return String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNum)
        } else {
            var components: [String] = []
            // Vol.X
            if let volumeNum = chapter.volumeNum {
                components.append(
                    String(format: NSLocalizedString("VOL_X", comment: ""), volumeNum)
                )
            }
            // Ch.X
            if let chapterNum = chapter.chapterNum {
                components.append(
                    String(format: NSLocalizedString("CH_X", comment: ""), chapterNum)
                )
            }
            // title
            if let title = chapter.title {
                if !components.isEmpty {
                    components.append("-")
                }
                components.append(title)
            }
            return components.joined(separator: " ")
        }
    }

    /// Returns a formatted subtitle for provided chapter and current page number.
    /// `date • page • scanlator • lang`
    private func makeSubtitle(chapter: Chapter, page: Int?) -> String? {
        var components: [String] = []
        // date
        if let dateUploaded = chapter.dateUploaded {
            components.append(DateFormatter.localizedString(from: dateUploaded, dateStyle: .medium, timeStyle: .none))
        }
        // page (if reading in progress)
        if let page = page, page > 0 {
            components.append(String(format: NSLocalizedString("PAGE_X", comment: ""), page))
        }
        // scanlator
        if let scanlator = chapter.scanlator {
            components.append(scanlator)
        }
        // language (if source has multiple enabled)
        if
            let languageCount = UserDefaults.standard.array(forKey: "\(chapter.sourceId).languages")?.count,
            languageCount > 1
        {
            components.append(chapter.lang)
        }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

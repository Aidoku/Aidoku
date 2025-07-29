//
//  ChapterCellConfiguration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import Gifu
import Nuke
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

private class ChapterCellContentView: UIView, UIContentView {
    var configuration: UIContentConfiguration {
        didSet {
            configure()
        }
    }

    private var thumbnailImageView: GIFImageView?

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
        progressView.radius = 13 / 2
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

    private lazy var lockedView: UIImageView = {
        let downloadedView = UIImageView(image: UIImage(systemName: "lock.fill"))
        downloadedView.contentMode = .scaleAspectFit
        downloadedView.frame = CGRect(x: 0, y: 0, width: 15, height: 15)
        downloadedView.tintColor = .label
        return downloadedView
    }()

    private lazy var titleLabelLeadingContraint: NSLayoutConstraint =
        titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12)
    private lazy var subtitleLabelLeadingContraint: NSLayoutConstraint =
        subtitleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12)
    private lazy var accessoryViewTrailingConstraint: NSLayoutConstraint =
        accessoryView.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor, constant: -12)

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        accessoryView.addSubview(progressView)
        accessoryView.addSubview(downloadedView)
        accessoryView.addSubview(lockedView)
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
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessoryView.leadingAnchor, constant: -2),
            titleLabelLeadingContraint,

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8/3),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22/3),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: accessoryView.leadingAnchor, constant: -2),
            subtitleLabelLeadingContraint,

            accessoryView.widthAnchor.constraint(equalToConstant: 15),
            accessoryView.heightAnchor.constraint(equalToConstant: 15),
            accessoryView.centerYAnchor.constraint(equalTo: centerYAnchor),
            accessoryViewTrailingConstraint,

            heightAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
    }

    func configure() {
        guard let configuration = configuration as? ChapterCellConfiguration else { return }

        // thumbnail
        if configuration.chapter.thumbnail != nil {
            if thumbnailImageView == nil {
                thumbnailImageView = GIFImageView(image: .mangaPlaceholder)
                guard let thumbnailImageView else { return }
                loadThumbnail()
                thumbnailImageView.contentMode = .scaleAspectFill
                thumbnailImageView.layer.cornerCurve = .continuous
                thumbnailImageView.layer.cornerRadius = 5
                thumbnailImageView.clipsToBounds = true
                thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(thumbnailImageView)

                titleLabelLeadingContraint.constant = 40 + 12 + 8
                subtitleLabelLeadingContraint.constant = 40 + 12 + 8

                NSLayoutConstraint.activate([
                    thumbnailImageView.widthAnchor.constraint(equalToConstant: 40),
                    thumbnailImageView.heightAnchor.constraint(equalToConstant: 40),
                    thumbnailImageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12),
                    thumbnailImageView.centerYAnchor.constraint(equalTo: centerYAnchor)
                ])
            } else {
                thumbnailImageView?.image = nil
                loadThumbnail()
            }
        } else {
            titleLabelLeadingContraint.constant = 12
            subtitleLabelLeadingContraint.constant = 12
            thumbnailImageView?.removeFromSuperview()
            thumbnailImageView = nil
        }

        titleLabel.text = configuration.chapter.makeTitle()

        let locked = configuration.chapter.locked && !configuration.downloaded
        if locked {
            layer.opacity = 0.5
        } else {
            layer.opacity = 1
        }

        let isGray = configuration.read || locked
        titleLabel.textColor = isGray ? .secondaryLabel : .label
        subtitleLabel.text = makeSubtitle(chapter: configuration.chapter, page: configuration.currentPage)
        subtitleLabel.isHidden = subtitleLabel.text == nil
        downloadedView.isHidden = !configuration.downloaded
        lockedView.isHidden = !configuration.chapter.locked || configuration.downloaded
        progressView.isHidden = !configuration.downloading
        progressView.setProgress(value: configuration.downloadProgress, withAnimation: false)

        // move accessoryView out of the way if it's hidden
        if downloadedView.isHidden && progressView.isHidden && lockedView.isHidden {
            accessoryViewTrailingConstraint.constant = -12 + 15
        } else {
            accessoryViewTrailingConstraint.constant = -12
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

    func loadThumbnail() {
        guard
            let thumbnailImageView,
            let configuration = configuration as? ChapterCellConfiguration,
            let thumbnail = configuration.chapter.thumbnail,
            let url = URL(string: thumbnail)
        else { return }
        Task {
            let urlRequest = if let source = SourceManager.shared.source(for: configuration.chapter.sourceId) {
                await source.getModifiedImageRequest(url: url, context: nil)
            } else {
                URLRequest(url: url)
            }
            let request = ImageRequest(urlRequest: urlRequest)

            let cached = ImagePipeline.shared.cache.containsCachedImage(for: request)

            let imageTask = ImagePipeline.shared.imageTask(with: request)
            guard let response = try? await imageTask.response else { return }

            await MainActor.run {
                if cached {
                    thumbnailImageView.image = response.image
                } else {
                    UIView.transition(with: thumbnailImageView, duration: 0.3, options: .transitionCrossDissolve) {
                        thumbnailImageView.image = response.image
                    }
                }
                if response.container.type == .gif, let data = response.container.data {
                    thumbnailImageView.animate(withGIFData: data)
                }
            }
        }
    }
}

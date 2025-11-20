//
//  MangaListCell.swift
//  Aidoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import Gifu
import Nuke
import UIKit

class MangaListCell: UICollectionViewCell {
    private var sourceId: String?
    private var url: String?
    private var imageTask: ImageTask?

    private lazy var coverImageView = {
        let imageView = GIFImageView()
        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 5
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        return imageView
    }()

    private lazy var bookmarkImageView = {
        let bookmarkImageView = UIImageView()
        bookmarkImageView.contentMode = .scaleAspectFit
        return bookmarkImageView
    }()

    private lazy var titleStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }()

    private lazy var titleLabel = {
        let titleLabel = UILabel()
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .left
        return titleLabel
    }()

    private lazy var subtitleLabel  = {
        let subtitleLabel = UILabel()
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.textAlignment = .left
        return subtitleLabel
    }()

    private lazy var tagScrollView = TagScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        coverImageView.addSubview(bookmarkImageView)

        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(subtitleLabel)
        titleStackView.addArrangedSubview(tagScrollView)

        contentView.addSubview(coverImageView)
        contentView.addSubview(titleStackView)
    }

    func constrain() {
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        bookmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            coverImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            coverImageView.widthAnchor.constraint(equalToConstant: 100 * 2/3),
            coverImageView.heightAnchor.constraint(equalToConstant: 100),

            bookmarkImageView.trailingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: -8),
            bookmarkImageView.topAnchor.constraint(equalTo: coverImageView.topAnchor),
            bookmarkImageView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkImageView.heightAnchor.constraint(equalToConstant: 27),

            titleStackView.leadingAnchor.constraint(equalTo: coverImageView.trailingAnchor, constant: 12),
            titleStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    func configure(with manga: AidokuRunner.Manga, isBookmarked: Bool) {
        sourceId = manga.sourceKey
        titleLabel.text = manga.title
        subtitleLabel.text = manga.authors?.joined(separator: ", ")
        subtitleLabel.isHidden = subtitleLabel.text?.isEmpty ?? true
        bookmarkImageView.image = isBookmarked ? UIImage(systemName: "bookmark.fill") : nil

        if let tags = manga.tags, !tags.isEmpty {
            tagScrollView.tags = tags
            tagScrollView.isHidden = false
        } else {
            tagScrollView.isHidden = true
        }

        Task {
            await loadImage(url: manga.cover.flatMap { URL(string: $0) })
        }
    }

    func highlight() {
        alpha = 0.5
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? CATransaction.animationDuration() : 0) {
            self.alpha = 1
        }
    }
}

extension MangaListCell {
    private func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.coverImageView.stopAnimatingGIF()

        // ensure sources are loaded so we can get the modified image request
        await SourceManager.shared.loadSources()

        let urlRequest = if let fileUrl = url.toAidokuFileUrl() {
            URLRequest(url: fileUrl)
        } else if let sourceId, let source = SourceManager.shared.source(for: sourceId) {
            await source.getModifiedImageRequest(url: url, context: nil)
        } else {
            URLRequest(url: url)
        }

        self.url = (urlRequest.url ?? url).absoluteString

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [DownsampleProcessor(width: bounds.width)]
        )

        let cached = ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    if response.request.imageId != self.url {
                        return
                    }
                    Task { @MainActor in
                        if cached {
                            self.coverImageView.image = response.image
                        } else {
                            UIView.transition(
                                with: self.coverImageView,
                                duration: CATransaction.animationDuration(),
                                options: .transitionCrossDissolve
                            ) {
                                self.coverImageView.image = response.image
                            }
                        }
                        if response.container.type == .gif, let data = response.container.data {
                            self.coverImageView.animate(withGIFData: data)
                        }
                    }
                case .failure:
                    imageTask = nil
            }
        }
    }
}

private class TagScrollView: UIView {
    var tags: [String] = [] {
        didSet {
            stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for text in tags {
                let labelView = TagLabelView(text: text)
                labelView.isUserInteractionEnabled = false
                stackView.addArrangedSubview(labelView)
            }
        }
    }

    private let stackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .leading
        return stackView
    }()

    private lazy var scrollView = {
        let scrollView = UIScrollView()
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        return scrollView
    }()

    private let fadeView = {
        let fadeView = FadeView()
        fadeView.isUserInteractionEnabled = false
        return fadeView
    }()

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        scrollView.addSubview(stackView)
        addSubview(scrollView)
        addSubview(fadeView)
    }

    func constrain() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),

            fadeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: bottomAnchor),
            fadeView.widthAnchor.constraint(equalToConstant: 32)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stackView.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        updateFadeVisibility()
    }

    private func updateFadeVisibility() {
        let maxOffset = scrollView.contentSize.width - scrollView.bounds.width
        let isAtEnd = scrollView.contentOffset.x >= maxOffset - 1
        fadeView.isHidden = isAtEnd || maxOffset <= 0
    }
}

extension TagScrollView: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateFadeVisibility()
    }
}

private class FadeView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    init() {
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            configure()
        }
    }

    func configure() {
        guard let gradient = self.layer as? CAGradientLayer else { return }
        let backgroundColor = UIColor.systemBackground.resolvedColor(with: self.traitCollection)
        gradient.colors = [
            backgroundColor.withAlphaComponent(0).cgColor,
            backgroundColor.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
    }
}

private class TagLabelView: UIView {
    private lazy var label = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        return label
    }()

    init(text: String) {
        super.init(frame: .zero)
        label.text = text
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 6
        layer.masksToBounds = true

        addSubview(label)
    }

    func constrain() {
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
}

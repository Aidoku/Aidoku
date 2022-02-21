//
//  MangaViewHeaderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/21/22.
//

import UIKit
import Kingfisher

class MangaViewHeaderView: UIView {

    var host: UIViewController? {
        didSet {
            descriptionLabel.host = host
        }
    }

    var manga: Manga? {
        didSet {
            activateConstraints()
            updateViews()
        }
    }

    var inLibrary: Bool {
        guard let manga = manga else { return false }
        return DataManager.shared.libraryContains(manga: manga)
    }

    let contentStackView = UIStackView()

    let titleStackView = UIStackView()
    let coverImageView = UIImageView()
    let innerTitleStackView = UIStackView()
    let titleLabel = UILabel()
    let authorLabel = UILabel()
    let labelStackView = UIStackView()
    let statusView = UIView()
    let statusLabel = UILabel()
    let nsfwView = UIView()
    let nsfwLabel = UILabel()
    let buttonStackView = UIStackView()
    let bookmarkButton = UIButton(type: .roundedRect)
    let safariButton = UIButton(type: .roundedRect)
    let descriptionLabel = ExpandableTextView()
    let tagScrollView = UIScrollView()
    let readButton = UIButton(type: .roundedRect)
    let headerView = UIView()
    let headerTitle = UILabel()
    let sortButton = UIButton(type: .roundedRect)

    override var intrinsicContentSize: CGSize {
        CGSize(
            width: bounds.width,
            height: contentStackView.bounds.height + 10
        )
    }

    init(manga: Manga) {
        self.manga = manga
        super.init(frame: .zero)
        configureContents()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateViews() {
        let retry = DelayRetryStrategy(maxRetryCount: 5, retryInterval: .seconds(0.1))
        coverImageView.kf.setImage(
            with: URL(string: manga?.cover ?? ""),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: [
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(0.3)),
                .retryStrategy(retry),
                .cacheOriginalImage
            ]
        )
        titleLabel.text = manga?.title ?? "No Title"
        authorLabel.text = manga?.author ?? "No Author"

        let status: String
        switch manga?.status {
        case .ongoing: status = "Ongoing"
        case .cancelled: status = "Cancelled"
        case .completed: status = "Completed"
        case .hiatus: status = "Hiatus"
        default: status = "Unknown"
        }
        statusLabel.text = status

        self.statusView.isHidden = self.manga?.status == .unknown
        if manga?.nsfw == .safe {
            nsfwView.alpha = 0
        } else {
            if manga?.nsfw == .suggestive {
                nsfwLabel.text = "Suggestive"
                nsfwView.backgroundColor = .systemOrange.withAlphaComponent(0.3)
            } else if manga?.nsfw == .nsfw {
                nsfwLabel.text = "NSFW"
                nsfwView.backgroundColor = .systemRed.withAlphaComponent(0.3)
            }
            nsfwView.alpha = 1
        }
        if inLibrary {
            bookmarkButton.tintColor = .white
            bookmarkButton.backgroundColor = tintColor
        } else {
            bookmarkButton.tintColor = tintColor
            bookmarkButton.backgroundColor = .secondarySystemFill
        }

        descriptionLabel.text = manga?.description ?? "No Description"

        UIView.animate(withDuration: 0.3) {
            self.labelStackView.isHidden = self.manga?.status == .unknown && self.manga?.nsfw == .safe

            if (self.descriptionLabel.alpha == 0 || self.descriptionLabel.isHidden) && self.manga?.description != nil {
                self.descriptionLabel.alpha = 1
                self.descriptionLabel.isHidden = false
            }

            let targetAlpha: CGFloat = self.manga?.url == nil ? 0 : 1
            if self.safariButton.alpha != targetAlpha {
                self.safariButton.alpha = targetAlpha
            }
        } completion: { _ in
            // Necessary because pre-iOS 15 stack view won't adjust its size automatically for some reason
            self.labelStackView.isHidden = self.manga?.status == .unknown && self.manga?.nsfw == .safe
        }
        loadTags()
        layoutIfNeeded()
    }

    func configureContents() {
        contentStackView.distribution = .fill
        contentStackView.axis = .vertical
        contentStackView.spacing = 14
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStackView)

        titleStackView.distribution = .fillProportionally
        titleStackView.axis = .horizontal
        titleStackView.spacing = 12
        titleStackView.alignment = .bottom
        titleStackView.translatesAutoresizingMaskIntoConstraints = false

        // Cover image
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 5
        coverImageView.layer.cornerCurve = .continuous
        coverImageView.layer.borderWidth = 1
        coverImageView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        titleStackView.addArrangedSubview(coverImageView)

        innerTitleStackView.distribution = .fill
        innerTitleStackView.axis = .vertical
        innerTitleStackView.spacing = 4
        innerTitleStackView.alignment = .leading
        titleStackView.addArrangedSubview(innerTitleStackView)

        // Title
        titleLabel.numberOfLines = 3
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        innerTitleStackView.addArrangedSubview(titleLabel)

        // Author
        authorLabel.numberOfLines = 1
        authorLabel.font = .systemFont(ofSize: 16)
        authorLabel.textColor = .secondaryLabel
        innerTitleStackView.addArrangedSubview(authorLabel)
        innerTitleStackView.setCustomSpacing(7, after: authorLabel)

        // Labels
        labelStackView.distribution = .equalSpacing
        labelStackView.axis = .horizontal
        labelStackView.spacing = 6
        innerTitleStackView.addArrangedSubview(labelStackView)
        innerTitleStackView.setCustomSpacing(10, after: labelStackView)

        // Status label
        statusView.isHidden = manga?.status == .unknown
        statusView.backgroundColor = .tertiarySystemFill
        statusView.layer.cornerRadius = 6
        statusView.layer.cornerCurve = .continuous

        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(statusLabel)
        labelStackView.addArrangedSubview(statusView)

        // Content rating label
        nsfwView.layer.cornerRadius = 6
        nsfwView.layer.cornerCurve = .continuous

        nsfwLabel.textColor = .secondaryLabel
        nsfwLabel.font = .systemFont(ofSize: 10)
        nsfwLabel.textAlignment = .center
        nsfwLabel.translatesAutoresizingMaskIntoConstraints = false
        nsfwView.addSubview(nsfwLabel)
        labelStackView.addArrangedSubview(nsfwView)

        // Buttons
        buttonStackView.distribution = .equalSpacing
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = 8
        innerTitleStackView.addArrangedSubview(buttonStackView)

        // Bookmark button
        bookmarkButton.addTarget(self, action: #selector(bookmarkPressed), for: .touchUpInside)
        bookmarkButton.setImage(UIImage(systemName: "bookmark.fill",
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
                                for: .normal)
        bookmarkButton.layer.cornerRadius = 6
        bookmarkButton.layer.cornerCurve = .continuous
        bookmarkButton.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.addArrangedSubview(bookmarkButton)

        // Webview button
        if manga?.url == nil {
            safariButton.alpha = 0
        }
        safariButton.backgroundColor = .secondarySystemFill
        safariButton.setImage(UIImage(systemName: "safari",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
                              for: .normal)
        safariButton.layer.cornerRadius = 6
        safariButton.layer.cornerCurve = .continuous
        safariButton.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.addArrangedSubview(safariButton)

        contentStackView.addArrangedSubview(titleStackView)

        // Description
        descriptionLabel.host = host
        descriptionLabel.alpha = manga?.description == nil ? 0 : 1
        descriptionLabel.isHidden = manga?.description == nil
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(descriptionLabel)
        contentStackView.setCustomSpacing(12, after: descriptionLabel)

        tagScrollView.showsVerticalScrollIndicator = false
        tagScrollView.showsHorizontalScrollIndicator = false
        tagScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(tagScrollView)
        contentStackView.setCustomSpacing(16, after: tagScrollView)

        // Read button
        readButton.tintColor = .white
        readButton.setTitle("No chapters available", for: .normal)
        readButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        readButton.backgroundColor = tintColor
        readButton.layer.cornerRadius = 10
        readButton.layer.cornerCurve = .continuous
        readButton.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(readButton)
        contentStackView.setCustomSpacing(12, after: readButton)

        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.addArrangedSubview(headerView)

        // Chapter count header text
        headerTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerTitle)

        if #available(iOS 15.0, *) {
            sortButton.setImage(UIImage(systemName: "line.3.horizontal.decrease"), for: .normal)
        } else {
            sortButton.setImage(UIImage(systemName: "line.horizontal.3.decrease"), for: .normal)
        }
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(sortButton)

        activateConstraints()
        updateViews()

        contentStackView.frame = CGRect(origin: .zero, size: contentStackView.intrinsicContentSize)
    }

    func activateConstraints() {
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentStackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),

            coverImageView.widthAnchor.constraint(equalToConstant: 114),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 3/2),

            bookmarkButton.widthAnchor.constraint(equalToConstant: 40),
            bookmarkButton.heightAnchor.constraint(equalToConstant: 32),
            safariButton.widthAnchor.constraint(equalToConstant: 40),
            safariButton.heightAnchor.constraint(equalToConstant: 32),

            statusLabel.topAnchor.constraint(equalTo: statusView.topAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: 8),
            statusView.widthAnchor.constraint(equalTo: statusLabel.widthAnchor, constant: 16),
            statusView.heightAnchor.constraint(equalTo: statusLabel.heightAnchor, constant: 8),

            nsfwView.widthAnchor.constraint(equalTo: nsfwLabel.widthAnchor, constant: 16),
            nsfwView.heightAnchor.constraint(equalTo: nsfwLabel.heightAnchor, constant: 8),
            nsfwLabel.leadingAnchor.constraint(equalTo: nsfwView.leadingAnchor, constant: 8),
            nsfwLabel.topAnchor.constraint(equalTo: nsfwView.topAnchor, constant: 4),

            descriptionLabel.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),
            descriptionLabel.heightAnchor.constraint(equalTo: descriptionLabel.textLabel.heightAnchor),

            tagScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tagScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tagScrollView.heightAnchor.constraint(equalToConstant: 26),

            readButton.leadingAnchor.constraint(equalTo: contentStackView.leadingAnchor),
            readButton.trailingAnchor.constraint(equalTo: contentStackView.trailingAnchor),
            readButton.heightAnchor.constraint(equalToConstant: 38),

            headerView.heightAnchor.constraint(equalToConstant: 36),

            headerTitle.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            headerTitle.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            sortButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            sortButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        readButton.backgroundColor = tintColor
        if inLibrary {
            bookmarkButton.backgroundColor = tintColor
        } else {
            bookmarkButton.tintColor = tintColor
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        loadTags()
    }

    func loadTags() {
        for view in tagScrollView.subviews {
            view.removeFromSuperview()
        }

        var width: CGFloat = safeAreaInsets.left + 16
        for tag in manga?.tags ?? [] {
            let tagView = UIView()
            tagView.backgroundColor = .tertiarySystemFill
            tagView.layer.cornerRadius = 13
            tagView.translatesAutoresizingMaskIntoConstraints = false
            tagScrollView.addSubview(tagView)

            let tagLabel = UILabel()
            tagLabel.text = tag
            tagLabel.textColor = .secondaryLabel
            tagLabel.font = .systemFont(ofSize: 14)
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            tagView.addSubview(tagLabel)

            tagView.leadingAnchor.constraint(equalTo: tagScrollView.leadingAnchor, constant: width).isActive = true
            tagLabel.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: 12).isActive = true
            tagLabel.topAnchor.constraint(equalTo: tagView.topAnchor, constant: 4).isActive = true
            tagView.widthAnchor.constraint(equalTo: tagLabel.widthAnchor, constant: 24).isActive = true
            tagView.heightAnchor.constraint(equalTo: tagLabel.heightAnchor, constant: 8).isActive = true

            width += tagLabel.intrinsicContentSize.width + 24 + 10
        }
        tagScrollView.contentSize = CGSize(width: width + 16, height: 26)

        UIView.animate(withDuration: 0.3) {
            self.tagScrollView.isHidden = (self.manga?.tags ?? []).isEmpty
        } completion: { _ in
            self.tagScrollView.isHidden = (self.manga?.tags ?? []).isEmpty
        }
    }

    @objc func bookmarkPressed() {
        if let manga = manga {
            if inLibrary {
                DataManager.shared.delete(manga: manga)
            } else {
                _ = DataManager.shared.addToLibrary(manga: manga)
            }
            if inLibrary {
                bookmarkButton.tintColor = .white
                bookmarkButton.backgroundColor = tintColor
            } else {
                bookmarkButton.tintColor = tintColor
                bookmarkButton.backgroundColor = .secondarySystemFill
            }
        }
    }
}

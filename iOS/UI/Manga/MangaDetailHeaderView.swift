//
//  MangaDetailHeaderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import UIKit
import Nuke

protocol MangaDetailHeaderViewDelegate: AnyObject {
    func bookmarkPressed()
    func bookmarkHeld()
    func trackerPressed()
    func safariPressed()
    func safariHeld()
    func readPressed()
    func coverPressed()
}

class MangaDetailHeaderView: UIView {

    private var manga: Manga?

    private var continueReading: Bool = false
    private(set) var nextChapter: Chapter?

    weak var delegate: MangaDetailHeaderViewDelegate?
    weak var sizeChangeListener: SizeChangeListenerDelegate?

    private var cancelBookmarkPress = false
    private var cancelSafariButtonPress = false
    // MARK: Start View Configuration

    // main stack view (containing everything)
    lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.distribution = .fill
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    // cover, titleStack stack view
    private lazy var coverStackView: UIStackView = {
        let coverStackView = UIStackView()
        coverStackView.distribution = .equalSpacing
        coverStackView.axis = .horizontal
        coverStackView.spacing = 12
        coverStackView.alignment = .bottom
        return coverStackView
    }()

    // title, author, status, buttons stack view
    private lazy var titleStackView: UIStackView = {
        let titleStackView = UIStackView()
        titleStackView.distribution = .fill
        titleStackView.axis = .vertical
        titleStackView.spacing = 4
        titleStackView.alignment = .leading
        return titleStackView
    }()

    // cover image (not private since we can preload this)
    lazy var coverImageView: UIImageView = {
        let coverImageView = UIImageView()
        coverImageView.image = UIImage(named: "MangaPlaceholder")
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 5
        coverImageView.layer.cornerCurve = .continuous
        coverImageView.layer.borderWidth = 1
        coverImageView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.isUserInteractionEnabled = true
        return coverImageView
    }()

    // title label
    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()

        let titleLongPress = UILongPressGestureRecognizer(target: self, action: #selector(titlePressed))
        titleLabel.addGestureRecognizer(titleLongPress)

        titleLabel.numberOfLines = 3
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.isUserInteractionEnabled = true
        return titleLabel
    }()

    // author label
    private lazy var authorLabel: UILabel = {
        let authorLabel = UILabel()
        authorLabel.numberOfLines = 1
        authorLabel.font = .systemFont(ofSize: 16)
        authorLabel.textColor = .secondaryLabel
        authorLabel.adjustsFontSizeToFitWidth = true
        authorLabel.minimumScaleFactor = 0.6
        return authorLabel
    }()

    // status, content rating, source label stack view
    private lazy var labelStackView: UIStackView = {
        let labelStackView = UIStackView()
        labelStackView.distribution = .equalSpacing
        labelStackView.axis = .horizontal
        labelStackView.spacing = 6
        return labelStackView
    }()

    // status label (completed, ongoing, etc.)
    private lazy var statusLabelView = MangaLabelView()

    // content rating label (nsfw, suggestive)
    private lazy var contentRatingLabelView = MangaLabelView()

    // bookmark, track, web page buttons stack view
    private lazy var buttonStackView: UIStackView = {
        let labelStackView = UIStackView()
        labelStackView.distribution = .equalSpacing
        labelStackView.axis = .horizontal
        labelStackView.spacing = 8
        return labelStackView
    }()

    // add to library button
    lazy var bookmarkButton = makeActionButton(symbolName: "bookmark.fill")

    // tracker menu button
    private lazy var trackerButton = makeActionButton(symbolName: "clock.arrow.2.circlepath")

    // view web page button
    private lazy var safariButton = makeActionButton(symbolName: "safari")

    /// Returns a button for use in `buttonStackView`.
    func makeActionButton(symbolName: String) -> UIButton {
        let button = UIButton(type: .roundedRect)
        button.setImage(
            UIImage(
                systemName: symbolName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            ),
            for: .normal
        )
        button.layer.cornerRadius = 6
        button.layer.cornerCurve = .continuous
        button.backgroundColor = .secondarySystemFill
        button.frame.size = CGSize(width: 40, height: 32)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // source name label (shown in library)
    private lazy var sourceLabelView: MangaLabelView = {
        let sourceLabelView = MangaLabelView()
        sourceLabelView.backgroundColor = UIColor(red: 0.25, green: 0.55, blue: 1, alpha: 0.3)
        return sourceLabelView
    }()

    // description label
    private lazy var descriptionLabel: ExpandableTextView = {
        let descriptionLabel = ExpandableTextView()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        return descriptionLabel
    }()

    // tag scroll view (holds tag stack view)
    private lazy var tagScrollView: UIScrollView = {
        let tagScrollView = UIScrollView()
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            tagScrollView.transform = CGAffineTransform(scaleX: -1, y: 1)
        }
        tagScrollView.showsVerticalScrollIndicator = false
        tagScrollView.showsHorizontalScrollIndicator = false
        tagScrollView.translatesAutoresizingMaskIntoConstraints = false
        tagScrollView.clipsToBounds = false
        return tagScrollView
    }()

    // tag stack view (holds tag views)
    private lazy var tagStackView: UIStackView = {
        let tagStackView = UIStackView()
        tagStackView.distribution = .equalSpacing
        tagStackView.axis = .horizontal
        tagStackView.spacing = 10
        tagStackView.alignment = .leading
        tagStackView.translatesAutoresizingMaskIntoConstraints = false
        return tagStackView
    }()

    // continue/start reading button
    private lazy var readButton: UIButton = {
        let readButton = UIButton(type: .roundedRect)
        readButton.setTitle(NSLocalizedString("NO_CHAPTERS_AVAILABLE", comment: ""), for: .normal)
        readButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        readButton.tintColor = .white
        readButton.backgroundColor = tintColor
        readButton.layer.cornerRadius = 10
        readButton.layer.cornerCurve = .continuous
        readButton.translatesAutoresizingMaskIntoConstraints = false
        return readButton
    }()

    // MARK: End View Configuration

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        readButton.backgroundColor = tintColor
    }

    private func configure() {
        descriptionLabel.sizeChangeListener = self

        bookmarkButton.addTarget(self, action: #selector(bookmarkPressed), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkHoldBegan), for: .touchDown)
        bookmarkButton.addTarget(self, action: #selector(bookmarkHoldCancelled), for: .touchCancel)
        bookmarkButton.addTarget(self, action: #selector(bookmarkHoldCancelled), for: .touchDragExit)
        safariButton.addTarget(self, action: #selector(safariPressed), for: .touchUpInside)
        safariButton.addTarget(self, action: #selector(safariHoldBegan), for: .touchDown)
        safariButton.addTarget(self, action: #selector(safariHoldCancelled), for: [.touchCancel, .touchDragExit])
        trackerButton.addTarget(self, action: #selector(trackerPressed), for: .touchUpInside)
        readButton.addTarget(self, action: #selector(readPressed), for: .touchUpInside)

        let coverImageLongPress = TouchDownGestureRecognizer(target: self, action: #selector(coverPressed))
        coverImageView.addGestureRecognizer(coverImageLongPress)
        coverImageView.addOverlay(color: .black)

        trackerButton.isHidden = !TrackerManager.shared.hasAvailableTrackers

        addSubview(stackView)
        stackView.addArrangedSubview(coverStackView)
        coverStackView.addArrangedSubview(coverImageView)
        coverStackView.addArrangedSubview(titleStackView)
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(authorLabel)
        titleStackView.setCustomSpacing(7, after: authorLabel)
        titleStackView.addArrangedSubview(labelStackView)
        labelStackView.addArrangedSubview(statusLabelView)
        labelStackView.addArrangedSubview(contentRatingLabelView)
        labelStackView.addArrangedSubview(sourceLabelView)
        titleStackView.setCustomSpacing(10, after: labelStackView)
        titleStackView.addArrangedSubview(buttonStackView)
        buttonStackView.addArrangedSubview(bookmarkButton)
        buttonStackView.addArrangedSubview(trackerButton)
        buttonStackView.addArrangedSubview(safariButton)
        stackView.addArrangedSubview(descriptionLabel)
        stackView.setCustomSpacing(12, after: descriptionLabel)
        stackView.addArrangedSubview(tagScrollView)
        stackView.setCustomSpacing(16, after: tagScrollView)
        tagScrollView.addSubview(tagStackView)
        stackView.addArrangedSubview(readButton)
    }

    private func constrain() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),

            coverImageView.widthAnchor.constraint(equalToConstant: 114),
            coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor, multiplier: 3/2),

            bookmarkButton.widthAnchor.constraint(equalToConstant: bookmarkButton.frame.size.width),
            bookmarkButton.heightAnchor.constraint(equalToConstant: bookmarkButton.frame.size.height),
            trackerButton.widthAnchor.constraint(equalToConstant: trackerButton.frame.size.width),
            trackerButton.heightAnchor.constraint(equalToConstant: trackerButton.frame.size.height),
            safariButton.widthAnchor.constraint(equalToConstant: safariButton.frame.size.width),
            safariButton.heightAnchor.constraint(equalToConstant: safariButton.frame.size.height),

            tagScrollView.heightAnchor.constraint(equalToConstant: 26),
            tagScrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            tagStackView.topAnchor.constraint(equalTo: tagScrollView.topAnchor),
            tagStackView.bottomAnchor.constraint(equalTo: tagScrollView.bottomAnchor),
            tagStackView.leadingAnchor.constraint(equalTo: tagScrollView.leadingAnchor),
            tagStackView.trailingAnchor.constraint(equalTo: tagScrollView.trailingAnchor),

            readButton.heightAnchor.constraint(equalToConstant: 38),
            readButton.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])
    }

    func configure(with manga: Manga) {
        self.manga = manga

        titleLabel.text = manga.title ?? NSLocalizedString("UNTITLED", comment: "")
        authorLabel.text = manga.author
        descriptionLabel.text = manga.description
        descriptionLabel.alpha = manga.description == nil ? 0 : 1 // for animating in

        let status: String
        switch manga.status {
        case .ongoing: status = NSLocalizedString("ONGOING", comment: "")
        case .cancelled: status = NSLocalizedString("CANCELLED", comment: "")
        case .completed: status = NSLocalizedString("COMPLETED", comment: "")
        case .hiatus: status = NSLocalizedString("HIATUS", comment: "")
        case .notPublished: status = NSLocalizedString("UPCOMING", comment: "")
        case .unknown: status = NSLocalizedString("UNKNOWN", comment: "")
        }
        statusLabelView.text = status
        statusLabelView.isHidden = manga.status == .unknown

        switch manga.nsfw {
        case .nsfw:
            contentRatingLabelView.text = NSLocalizedString("NSFW", comment: "")
            contentRatingLabelView.backgroundColor = .systemRed.withAlphaComponent(0.3)
            contentRatingLabelView.isHidden = false
        case .suggestive:
            contentRatingLabelView.text = NSLocalizedString("SUGGESTIVE", comment: "")
            contentRatingLabelView.backgroundColor = .systemOrange.withAlphaComponent(0.3)
            contentRatingLabelView.isHidden = false
        case .safe:
            contentRatingLabelView.isHidden = true
        }

        let isTracking = TrackerManager.shared.isTracking(sourceId: manga.sourceId, mangaId: manga.id)
        trackerButton.tintColor = isTracking ? .white : tintColor
        trackerButton.backgroundColor = isTracking ? tintColor : .secondarySystemFill

        safariButton.isHidden = manga.url == nil

        load(tags: manga.tags ?? [])

        updateReadButtonTitle(nextChapter: nextChapter, continueReading: continueReading)
        scaleTitle()

        UIView.animate(withDuration: 0.3) {
            self.authorLabel.isHidden = manga.author == nil
            self.descriptionLabel.isHidden = manga.description == nil
            self.labelStackView.isHidden = manga.status == .unknown && manga.nsfw == .safe
        }

        Task {
            let inLibrary = await CoreDataManager.shared.container.performBackgroundTask { context in
                CoreDataManager.shared.hasLibraryManga(
                    sourceId: manga.sourceId,
                    mangaId: manga.id,
                    context: context
                )
            }
            let showSourceLabel = inLibrary && UserDefaults.standard.bool(forKey: "General.showSourceLabel")
            if showSourceLabel, let source = SourceManager.shared.source(for: manga.sourceId) {
                sourceLabelView.text = source.manifest.info.name
                sourceLabelView.isHidden = false
            } else {
                sourceLabelView.isHidden = true
            }

            bookmarkButton.tintColor = inLibrary ? .white : tintColor
            bookmarkButton.backgroundColor = inLibrary ? tintColor : .secondarySystemFill

            UIView.animate(withDuration: 0.3) {
                self.labelStackView.isHidden = manga.status == .unknown && manga.nsfw == .safe && !showSourceLabel
            }

            if let url = manga.coverUrl {
                await setCover(url: url, sourceId: manga.sourceId)
            }
        }
    }

    func scaleTitle() {
        if superview != nil {
            layoutIfNeeded()
        }

        guard titleLabel.bounds.size.height > 0 else { return }

        // check title label size
        let titleSize: CGSize = ((titleLabel.text ?? "") as NSString).boundingRect(
            with: CGSize(width: titleLabel.frame.size.width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: [.font: titleLabel.font ?? .systemFont(ofSize: 22, weight: .semibold)],
            context: nil
        ).size

        // if text isn't truncated we don't need to scale
        guard titleSize.height > titleLabel.bounds.size.height else { return }

        let scaleFactor: CGFloat = max(titleLabel.bounds.size.height / titleSize.height, 0.75)

        titleLabel.numberOfLines = Int((3 / scaleFactor).rounded(.up))
        titleLabel.font = .systemFont(ofSize: 22 * scaleFactor, weight: .semibold)
        authorLabel.font = .systemFont(ofSize: 16 * scaleFactor, weight: .regular)

        setNeedsLayout()
    }

    private func setCover(url: URL, sourceId: String? = nil) async {
        Task { @MainActor in
            if coverImageView.image == nil {
                coverImageView.image = UIImage(named: "MangaPlaceholder")
            }
        }

        var urlRequest = URLRequest(url: url)

        if
            let sourceId = sourceId,
            let source = SourceManager.shared.source(for: sourceId),
            source.handlesImageRequests,
            let request = try? await source.getImageRequest(url: url.absoluteString)
        {
            urlRequest.url = URL(string: request.URL ?? "")
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [DownsampleProcessor(width: bounds.width)]
        )

        guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
        Task { @MainActor in
            UIView.transition(with: coverImageView, duration: 0.3, options: .transitionCrossDissolve) {
                self.coverImageView.image = image
            }
        }
    }

    private func load(tags: [String]) {
        for view in tagStackView.subviews {
            view.removeFromSuperview()
        }

        for tag in tags {
            let tagView = UIView()
            tagView.backgroundColor = .tertiarySystemFill
            tagView.layer.cornerRadius = 13
            tagView.translatesAutoresizingMaskIntoConstraints = false
            if effectiveUserInterfaceLayoutDirection == .rightToLeft {
                tagView.transform = CGAffineTransform(scaleX: -1, y: 1)
            }
            tagScrollView.addSubview(tagView)

            let tagLabel = UILabel()
            tagLabel.text = tag
            tagLabel.textColor = .secondaryLabel
            tagLabel.font = .systemFont(ofSize: 14)
            tagLabel.translatesAutoresizingMaskIntoConstraints = false
            tagView.addSubview(tagLabel)

            tagStackView.addArrangedSubview(tagView)

            NSLayoutConstraint.activate([
                tagLabel.leadingAnchor.constraint(equalTo: tagView.leadingAnchor, constant: 12),
                tagLabel.topAnchor.constraint(equalTo: tagView.topAnchor, constant: 4),
                tagView.widthAnchor.constraint(equalTo: tagLabel.widthAnchor, constant: 24),
                tagView.heightAnchor.constraint(equalTo: tagLabel.heightAnchor, constant: 8)
            ])
        }

        UIView.animate(withDuration: 0.3) {
            self.tagScrollView.isHidden = tags.isEmpty
        }
    }

    func reloadBookmarkButton(inLibrary: Bool? = nil) {
        guard let manga = manga else { return }
        let inLibrary = inLibrary ?? CoreDataManager.shared.hasLibraryManga(sourceId: manga.sourceId, mangaId: manga.id)
        bookmarkButton.tintColor = inLibrary ? .white : tintColor
        bookmarkButton.backgroundColor = inLibrary ? tintColor : .secondarySystemFill
    }

    func reloadTrackerButton() {
        if let manga = manga {
            let isTracking = TrackerManager.shared.isTracking(sourceId: manga.sourceId, mangaId: manga.id)
            trackerButton.tintColor = isTracking ? .white : tintColor
            trackerButton.backgroundColor = isTracking ? tintColor : .secondarySystemFill
        }
        trackerButton.isHidden = !TrackerManager.shared.hasAvailableTrackers
    }

    func updateReadButtonTitle(
        nextChapter: Chapter? = nil,
        continueReading: Bool = false,
        allRead: Bool = false
    ) {
        guard let manga = manga else { return }
        self.nextChapter = nextChapter
        self.continueReading = continueReading
        readButton.isUserInteractionEnabled = true
        var title = ""
        if allRead {
            title = NSLocalizedString("ALL_CHAPTERS_READ", comment: "")
            readButton.isUserInteractionEnabled = false
        } else if SourceManager.shared.source(for: manga.sourceId) == nil {
            title = NSLocalizedString("UNAVAILABLE", comment: "")
            readButton.isUserInteractionEnabled = false
        } else if let chapter = nextChapter {
            if !continueReading {
                title = NSLocalizedString("START_READING", comment: "")
            } else {
                title = NSLocalizedString("CONTINUE_READING", comment: "")
            }
            if let volumeNum = chapter.volumeNum {
                title += " " + String(format: NSLocalizedString("VOL_X", comment: ""), volumeNum)
            }
            if let chapterNum = chapter.chapterNum {
                title += " " + String(format: NSLocalizedString("CH_X", comment: ""), chapterNum)
            }
        } else {
            title = NSLocalizedString("NO_CHAPTERS_AVAILABLE", comment: "")
        }
        readButton.setTitle(title, for: .normal)
    }

    @objc private func bookmarkPressed() {
        guard !cancelBookmarkPress else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        delegate?.bookmarkPressed()
    }
    @objc private func bookmarkHeld() {
        cancelBookmarkPress = true
        delegate?.bookmarkHeld()
    }
    @objc private func trackerPressed() {
        delegate?.trackerPressed()
    }
    @objc private func safariPressed() {
        delegate?.safariPressed()
    }
    @objc private func safariHeld() {
        cancelSafariButtonPress = true
        delegate?.safariHeld()
    }
    @objc private func readPressed() {
        delegate?.readPressed()
    }
    @objc private func coverPressed(_ sender: TouchDownGestureRecognizer) {
        switch sender.state {
        case .began:
            coverImageView.showOverlay(color: .black, alpha: 0.5)
        case .ended:
            delegate?.coverPressed()
            UIView.transition(with: coverImageView, duration: 0.35, options: [.allowAnimatedContent, .allowUserInteraction]) {
                self.coverImageView.hideOverlay(color: .black)
            }
        case .cancelled:
            UIView.transition(with: coverImageView, duration: 0.35, options: [.allowAnimatedContent, .allowUserInteraction]) {
                self.coverImageView.hideOverlay(color: .black)
            }
        default:
            break
        }
    }

    @objc private func bookmarkHoldBegan() {
        cancelBookmarkPress = false
        perform(#selector(bookmarkHeld), with: nil, afterDelay: 0.6)
    }
    @objc private func bookmarkHoldCancelled() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }

    @objc private func titlePressed(_ recognizer: UIGestureRecognizer) {
        guard
            recognizer.state == .began,
            let recognizerView = recognizer.view
        else { return }
        let menuController = UIMenuController.shared
        menuController.menuItems = [UIMenuItem(title: NSLocalizedString("COPY", comment: ""), action: #selector(copyTitleText))]
        menuController.showMenu(from: recognizerView, rect: recognizerView.frame)
    }

    @objc private func copyTitleText() {
        UIPasteboard.general.string = titleLabel.text
    }

    @objc private func safariHoldBegan() {
        cancelSafariButtonPress = false
        perform(#selector(safariHeld), with: nil, afterDelay: 0.6)
    }

    @objc private func safariHoldCancelled() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }
}

extension MangaDetailHeaderView: SizeChangeListenerDelegate {
    func sizeChanged(_ newSize: CGSize) {
        sizeChangeListener?.sizeChanged(bounds.size)
    }
}

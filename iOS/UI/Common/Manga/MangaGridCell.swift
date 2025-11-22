//
//  MangaGridCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/24/22.
//

import Gifu
import Nuke
import UIKit

class MangaGridCell: UICollectionViewCell {
    var sourceId: String?
    var mangaId: String?

    var title: String? {
        get {
            titleLabel.text
        }
        set {
            titleLabel.text = newValue ?? NSLocalizedString("UNTITLED")
        }
    }

    var showsBookmark: Bool {
        get {
            !bookmarkView.isHidden
        }
        set {
            bookmarkView.isHidden = !newValue
        }
    }

    var badgeNumber: Int {
        get { badgeView.badgeNumber }
        set { badgeView.badgeNumber = newValue }
    }
    var badgeNumber2: Int {
        get { badgeView.badgeNumber2 }
        set { badgeView.badgeNumber2 = newValue }
    }

    let imageView = GIFImageView()
    private let titleLabel = UILabel()
    private let overlayView = UIView()
    private let gradient = CAGradientLayer()

    private lazy var badgeView = DoubleBadgeView()

    private let bookmarkView = UIImageView()
    private let highlightView = UIView()

    private var url: String?
    private var imageTask: ImageTask?
    var isEditing = false

    // shadow shown when in selection mode
    private lazy var shadowOverlayView: UIView = {
        let shadowOverlayView = UIView()
        shadowOverlayView.alpha = 0
        shadowOverlayView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        shadowOverlayView.layer.cornerRadius = layer.cornerRadius
        shadowOverlayView.translatesAutoresizingMaskIntoConstraints = false
        return shadowOverlayView
    }()

    // selection circle in bottom right
    private lazy var selectionView: UIView = {
        let selectionView = UIView()
        selectionView.frame.size = CGSize(width: 24, height: 24)
        selectionView.layer.cornerRadius = 12
        selectionView.layer.borderColor = UIColor.white.cgColor
        selectionView.layer.borderWidth = 2
        selectionView.translatesAutoresizingMaskIntoConstraints = false

        let innerCircleView = UIView()
        innerCircleView.frame = CGRect(x: 3, y: 3, width: 18, height: 18)
        innerCircleView.backgroundColor = .white
        innerCircleView.layer.cornerRadius = 10
        selectionView.addSubview(innerCircleView)

        selectionView.layer.shadowOpacity = 0
        selectionView.layer.shadowOffset = .zero
        selectionView.layer.shadowRadius = 0

        return selectionView
    }()

    // checkmark icon shown in selection circle when selected
    private lazy var checkmarkImageView: UIImageView = {
        let checkmarkImageView = UIImageView()
        checkmarkImageView.image = UIImage(
            systemName: "checkmark.circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)
        )
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false
        return checkmarkImageView
    }()

    private var badgeConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 5
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.quaternarySystemFill.cgColor

        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)

        gradient.frame = bounds
        gradient.locations = [0.6, 1]
        gradient.colors = [
            UIColor(white: 0, alpha: 0).cgColor,
            UIColor(white: 0, alpha: 0.7).cgColor
        ]
        gradient.cornerRadius = layer.cornerRadius
        gradient.needsDisplayOnBoundsChange = true

        overlayView.layer.insertSublayer(gradient, at: 0)
        overlayView.layer.cornerRadius = layer.cornerRadius
        contentView.addSubview(overlayView)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        contentView.addSubview(titleLabel)

        contentView.addSubview(badgeView)

        bookmarkView.isHidden = true
        bookmarkView.image = UIImage(named: "bookmark")
        bookmarkView.contentMode = .scaleAspectFit
        contentView.addSubview(bookmarkView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        contentView.addSubview(highlightView)

        shadowOverlayView.alpha = 0
        selectionView.alpha = 0
        checkmarkImageView.isHidden = true
        contentView.addSubview(shadowOverlayView)
        contentView.addSubview(selectionView)
        selectionView.addSubview(checkmarkImageView)
    }

    func constrain() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        bookmarkView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            badgeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),

            bookmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            bookmarkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bookmarkView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkView.heightAnchor.constraint(equalToConstant: 27),

            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor),
            highlightView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            highlightView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            shadowOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            shadowOverlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            shadowOverlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            shadowOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            selectionView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -10),
            selectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            selectionView.widthAnchor.constraint(equalToConstant: selectionView.frame.width),
            selectionView.heightAnchor.constraint(equalToConstant: selectionView.frame.height),

            checkmarkImageView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = UIImage(named: "MangaPlaceholder")
        imageTask?.cancel()
        imageTask = nil
    }
}

extension MangaGridCell {
    func highlight() {
        highlightView.alpha = 1
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }

    func setEditing(_ editing: Bool, animated: Bool = true) {
        guard isEditing != editing else { return }
        isEditing = editing
        if editing {
            checkmarkImageView.isHidden = true
        }
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.shadowOverlayView.alpha = editing ? 1 : 0
            self.selectionView.alpha = editing ? 1 : 0
        }
    }

    func setSelected(_ selected: Bool, animated: Bool = true) {
        guard isEditing else { return }
        checkmarkImageView.isHidden = !selected
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.shadowOverlayView.alpha = selected ? 0 : 1
                self.selectionView.layer.shadowOpacity = selected ? 1 : 0
            }
        } else {
            self.shadowOverlayView.alpha = selected ? 0 : 1
            self.selectionView.layer.shadowOpacity = selected ? 1 : 0
        }
    }
}

extension MangaGridCell {
    func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.imageView.stopAnimatingGIF()

        var urlRequest = URLRequest(url: url)
        var cached = ImagePipeline.shared.cache.containsCachedImage(for: .init(urlRequest: urlRequest))

        if !cached {
            if let fileUrl = url.toAidokuFileUrl() {
                urlRequest = URLRequest(url: fileUrl)
            } else if let sourceId {
                // ensure sources are loaded so we can get the modified image request
                await SourceManager.shared.loadSources()
                if let source = SourceManager.shared.source(for: sourceId) {
                    urlRequest = await source.getModifiedImageRequest(url: url, context: nil)
                }
            }
        }

        self.url = (urlRequest.url ?? url).absoluteString

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [DownsampleProcessor(width: bounds.width)]
        )

        cached = cached || ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    if response.request.imageId != self.url {
                        return
                    }
                    Task { @MainActor in
                        if cached {
                            self.imageView.image = response.image
                        } else {
                            UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve) {
                                self.imageView.image = response.image
                            }
                        }
                        if response.container.type == .gif, let data = response.container.data {
                            self.imageView.animate(withGIFData: data)
                        }
                    }
                case .failure:
                    imageTask = nil
            }
        }
    }
}

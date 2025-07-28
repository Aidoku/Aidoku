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
            titleLabel.text = newValue ?? NSLocalizedString("UNTITLED", comment: "")
        }
    }

    var badgeNumber: Int {
        get {
            Int(badgeLabel.text ?? "") ?? 0
        }
        set {
            badgeLabel.text = newValue == 0 ? nil : String(newValue)
            badgeView.isHidden = badgeLabel.text == nil
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

    let imageView = GIFImageView()
    private let titleLabel = UILabel()
    private let overlayView = UIView()
    private let gradient = CAGradientLayer()
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        clipsToBounds = true
        layer.cornerRadius = 5

        layer.borderWidth = 1
        layer.borderColor = UIColor.quaternarySystemFill.cgColor

        imageView.image = UIImage(named: "MangaPlaceholder")
        imageView.contentMode = .scaleAspectFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

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
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        badgeView.isHidden = true
        badgeView.backgroundColor = tintColor
        badgeView.layer.cornerRadius = 5
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeView)

        badgeLabel.textColor = .white
        badgeLabel.numberOfLines = 1
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)

        bookmarkView.isHidden = true
        bookmarkView.image = UIImage(named: "bookmark")
        bookmarkView.contentMode = .scaleAspectFit
        bookmarkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bookmarkView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightView)

        shadowOverlayView.alpha = 0
        selectionView.alpha = 0
        checkmarkImageView.isHidden = true
        addSubview(shadowOverlayView)
        addSubview(selectionView)
        selectionView.addSubview(checkmarkImageView)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leftAnchor.constraint(equalTo: leftAnchor),
            imageView.rightAnchor.constraint(equalTo: rightAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.leftAnchor.constraint(equalTo: leftAnchor),
            overlayView.rightAnchor.constraint(equalTo: rightAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10),
            badgeView.heightAnchor.constraint(equalToConstant: 20),

            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            bookmarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bookmarkView.topAnchor.constraint(equalTo: topAnchor),
            bookmarkView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkView.heightAnchor.constraint(equalToConstant: 27),

            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.leftAnchor.constraint(equalTo: leftAnchor),
            highlightView.rightAnchor.constraint(equalTo: rightAnchor),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor),

            shadowOverlayView.topAnchor.constraint(equalTo: topAnchor),
            shadowOverlayView.leftAnchor.constraint(equalTo: leftAnchor),
            shadowOverlayView.rightAnchor.constraint(equalTo: rightAnchor),
            shadowOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),

            selectionView.rightAnchor.constraint(equalTo: rightAnchor, constant: -10),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            selectionView.widthAnchor.constraint(equalToConstant: selectionView.frame.width),
            selectionView.heightAnchor.constraint(equalToConstant: selectionView.frame.height),

            checkmarkImageView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        gradient.frame = bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = UIImage(named: "MangaPlaceholder")
        imageTask?.cancel()
        imageTask = nil
    }

    override func tintColorDidChange() {
        badgeView.backgroundColor = tintColor
    }

    func loadImage(url: URL?) async {
        guard let url else { return }

        if let imageTask, imageTask.state == .running {
            return
        }

        self.imageView.stopAnimatingGIF()

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

    func highlight() {
        highlightView.alpha = 1
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }

    func setEditing(_ editing: Bool, animated: Bool = true) {
        isEditing = editing
        if editing {
            checkmarkImageView.isHidden = true
        }
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.shadowOverlayView.alpha = editing ? 1 : 0
            self.selectionView.alpha = editing ? 1 : 0
        }
    }

    func select(animated: Bool = true) {
        guard isEditing else { return }
        checkmarkImageView.isHidden = false
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.shadowOverlayView.alpha = 0
            self.selectionView.layer.shadowOpacity = 1
        }
    }

    func deselect(animated: Bool = true) {
        guard isEditing else { return }
        checkmarkImageView.isHidden = true
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.shadowOverlayView.alpha = 1
            self.selectionView.layer.shadowOpacity = 0
        }
    }
}

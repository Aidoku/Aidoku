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
            updateBadgeLayout()
        }
    }
    var badgeNumber2: Int {
        get {
            Int(badgeLabel2.text ?? "") ?? 0
        }
        set {
            badgeLabel2.text = newValue == 0 ? nil : String(newValue)
            badgeView2.isHidden = badgeLabel2.text == nil
            updateBadgeLayout()
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

    private lazy var badgeView = {
        let badgeView = UIView()
        badgeView.isHidden = true
        badgeView.backgroundColor = tintColor
        badgeView.layer.cornerRadius = 5
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)
        return badgeView
    }()

    private let badgeLabel = {
        let badgeLabel = UILabel()
        badgeLabel.textColor = .white
        badgeLabel.numberOfLines = 1
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        return badgeLabel
    }()

    private lazy var badgeView2 = {
        let badgeView = UIView()
        badgeView.isHidden = true
        badgeView.backgroundColor = .systemIndigo
        badgeView.layer.cornerRadius = 5
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel2)
        return badgeView
    }()

    private let badgeLabel2 = {
        let badgeLabel = UILabel()
        badgeLabel.textColor = .white
        badgeLabel.numberOfLines = 1
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        return badgeLabel
    }()

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
        imageView.translatesAutoresizingMaskIntoConstraints = false
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
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(overlayView)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        contentView.addSubview(badgeView)
        contentView.addSubview(badgeView2)

        bookmarkView.isHidden = true
        bookmarkView.image = UIImage(named: "bookmark")
        bookmarkView.contentMode = .scaleAspectFit
        bookmarkView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bookmarkView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(highlightView)

        shadowOverlayView.alpha = 0
        selectionView.alpha = 0
        checkmarkImageView.isHidden = true
        contentView.addSubview(shadowOverlayView)
        contentView.addSubview(selectionView)
        selectionView.addSubview(checkmarkImageView)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            imageView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            overlayView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10),
            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            badgeView2.widthAnchor.constraint(equalTo: badgeLabel2.widthAnchor, constant: 10),
            badgeView2.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel2.centerXAnchor.constraint(equalTo: badgeView2.centerXAnchor),
            badgeLabel2.centerYAnchor.constraint(equalTo: badgeView2.centerYAnchor),

            bookmarkView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            bookmarkView.topAnchor.constraint(equalTo: contentView.topAnchor),
            bookmarkView.widthAnchor.constraint(equalToConstant: 17),
            bookmarkView.heightAnchor.constraint(equalToConstant: 27),

            highlightView.topAnchor.constraint(equalTo: contentView.topAnchor),
            highlightView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            highlightView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            highlightView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            shadowOverlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            shadowOverlayView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            shadowOverlayView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            shadowOverlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            selectionView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -10),
            selectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            selectionView.widthAnchor.constraint(equalToConstant: selectionView.frame.width),
            selectionView.heightAnchor.constraint(equalToConstant: selectionView.frame.height),

            checkmarkImageView.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor)
        ])

        updateBadgeLayout()
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
        if tintAdjustmentMode == .dimmed {
            badgeView2.backgroundColor = .systemIndigo.grayscale()
        } else {
            badgeView2.backgroundColor = .systemIndigo
        }
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

    private func updateBadgeLayout() {
        NSLayoutConstraint.deactivate(badgeConstraints)
        if badgeNumber > 0 && badgeNumber2 > 0 {
            // both badges visible, show side by side
            badgeView.isHidden = false
            badgeView2.isHidden = false
            badgeView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner] // top-left, bottom-left
            badgeView2.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] // top-right, bottom-right
            badgeConstraints = [
                badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                badgeView2.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor),
                badgeView2.topAnchor.constraint(equalTo: badgeView.topAnchor)
            ]
            NSLayoutConstraint.activate(badgeConstraints)
        } else if badgeNumber > 0 {
            // only first badge visible
            badgeView.isHidden = false
            badgeView2.isHidden = true
            badgeView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            badgeConstraints = [
                badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5)
            ]
            NSLayoutConstraint.activate(badgeConstraints)
        } else if badgeNumber2 > 0 {
            // only second badge visible
            badgeView.isHidden = true
            badgeView2.isHidden = false
            badgeView2.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            badgeConstraints = [
                badgeView2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                badgeView2.topAnchor.constraint(equalTo: topAnchor, constant: 5)
            ]
            NSLayoutConstraint.activate(badgeConstraints)
        } else {
            badgeView.isHidden = true
            badgeView2.isHidden = true
        }
    }
}

private extension UIColor {
    /// Returns a grayscale version of the color.
    func grayscale() -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }

        let gray = red * 0.299 + green * 0.587 + blue * 0.114
        return UIColor(red: gray, green: gray, blue: gray, alpha: alpha)
    }
}

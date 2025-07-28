//
//  MangaCoverCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Nuke

class MangaCoverCell: UICollectionViewCell {

    var manga: Manga? {
        didSet {
            reloadData()
        }
    }

    var badgeNumber: Int? {
        didSet {
            if let num = badgeNumber, num > 0 {
                badgeLabel.text = String(num)
                UIView.animate(withDuration: 0.3) {
                    self.badgeView.alpha = 1
                } completion: { _ in
                    self.badgeView.alpha = 1
                }
            } else {
                UIView.animate(withDuration: 0.3) {
                    self.badgeView.alpha = 0
                } completion: { _ in
//                    self.badgeLabel.text = ""
                    self.badgeView.alpha = 0
                }
            }
        }
    }

    var showsLibraryBadge = false {
        didSet {
            UIView.animate(withDuration: 0.3) {
                if self.showsLibraryBadge {
                    self.libraryBadgeView.alpha = 1
                } else {
                    self.libraryBadgeView.alpha = 0
                }
            }
        }
    }

    var imageView = UIImageView()
    var titleLabel = UILabel()
    var gradient = CAGradientLayer()
    var badgeView = UIView()
    var badgeLabel = UILabel()
    var libraryBadgeView = UIImageView()

    var highlightView = UIView()

    private var imageTask: ImageTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        gradient.frame = bounds
    }

    func layoutViews() {
        for view in subviews {
            view.removeFromSuperview()
        }

        clipsToBounds = true
        layer.cornerRadius = 5

        layer.borderWidth = 1
        layer.borderColor = UIColor.quaternarySystemFill.cgColor

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

        let overlayView = UIView()
        overlayView.layer.insertSublayer(gradient, at: 0)
        overlayView.layer.cornerRadius = layer.cornerRadius
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)

        titleLabel.text = manga?.title ?? NSLocalizedString("UNTITLED", comment: "")
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        badgeView.alpha = 0
        badgeView.backgroundColor = tintColor
        badgeView.layer.cornerRadius = 5
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeView)

        badgeLabel.text = String(badgeNumber ?? 0)
        badgeLabel.textColor = .white
        badgeLabel.numberOfLines = 1
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)

        libraryBadgeView.alpha = 0
        libraryBadgeView.image = UIImage(named: "bookmark")
        libraryBadgeView.contentMode = .scaleAspectFit
        libraryBadgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(libraryBadgeView)

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightView)

        overlayView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        overlayView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        overlayView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        overlayView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        activateConstraints()

        if manga != nil {
            Task {
                await loadImage()
            }
        }
    }

    func reloadData() {
        titleLabel.text = manga?.title ?? NSLocalizedString("UNTITLED", comment: "")
        Task {
            await loadImage()
        }
    }

    func activateConstraints() {
        imageView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        imageView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        imageView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true

        badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5).isActive = true
        badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5).isActive = true
        badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10).isActive = true
        badgeView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor).isActive = true
        badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor).isActive = true

        libraryBadgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        libraryBadgeView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        libraryBadgeView.widthAnchor.constraint(equalToConstant: 17).isActive = true
        libraryBadgeView.heightAnchor.constraint(equalToConstant: 27).isActive = true

        highlightView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        highlightView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        highlightView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        highlightView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = UIImage(named: "MangaPlaceholder")
    }

    func highlight() {
        highlightView.alpha = 1
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }

    func loadImage() async {
        guard let url = manga?.coverUrl else {
            imageView.image = nil
            return
        }

        if imageTask != nil {
            return
        }

        Task { @MainActor in
            imageView.image = UIImage(named: "MangaPlaceholder")
        }

        let urlRequest = if let fileUrl = url.toAidokuFileUrl() {
            URLRequest(url: fileUrl)
        } else if let sourceId = manga?.sourceId, let source = SourceManager.shared.source(for: sourceId) {
            await source.getModifiedImageRequest(url: url, context: nil)
        } else {
            URLRequest(url: url)
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [DownsampleProcessor(width: bounds.width)]
        )

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                Task { @MainActor in
                    UIView.transition(with: self.imageView, duration: 0.3, options: .transitionCrossDissolve) {
                        self.imageView.image = response.image
                    }
                }
            case .failure:
                imageTask = nil
            }
        }
    }
}

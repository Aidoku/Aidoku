//
//  MangaCoverCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Nuke
import NukeExtensions

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

    var checkForRequestModifier = true

    var imageView = UIImageView()
    var titleLabel = UILabel()
    var gradient = CAGradientLayer()
    var badgeView = UIView()
    var badgeLabel = UILabel()
    var libraryBadgeView = UIImageView()

    var highlightView = UIView()

    init(manga: Manga) {
        super.init(frame: .zero)
        self.manga = manga
        layoutViews()
    }

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
        checkForRequestModifier = true
    }

    func highlight() {
        highlightView.alpha = 1
    }

    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }

    func getTintColor(from image: UIImage) {
        image.getColors(quality: .low) { colors in
            let luma = colors?.background.luminance ?? 0
            if luma >= 0.9 || luma <= 0.1, let secondary = colors?.secondary {
                self.manga?.tintColor = CodableColor(color: secondary)
            } else if let background = colors?.background {
                self.manga?.tintColor = CodableColor(color: background)
            } else {
                self.manga?.tintColor = nil
            }
        }
    }

    func loadImage() async {
        guard
            let urlString = manga?.cover,
            let url = URL(string: urlString)
        else {
            imageView.image = nil
            return
        }

        var urlRequest = URLRequest(url: url)

        if checkForRequestModifier,
           let sourceId = manga?.sourceId,
           let source = SourceManager.shared.source(for: sourceId),
           source.handlesImageRequests,
           let request = try? await source.getImageRequest(url: urlString) {

            urlRequest.url = URL(string: request.URL ?? "")
            for (key, value) in request.headers {
                urlRequest.setValue(value, forHTTPHeaderField: key)
            }
            if let body = request.body { urlRequest.httpBody = body }
            checkForRequestModifier = false
        }

        let request = ImageRequest(
            urlRequest: urlRequest,
            processors: [.resize(width: bounds.width)]
        )

        _ = NukeExtensions.loadImage(
            with: request,
            options: ImageLoadingOptions(
                placeholder: UIImage(named: "MangaPlaceholder"),
                transition: .fadeIn(duration: 0.3)
            ),
            into: imageView
        )
    }
}

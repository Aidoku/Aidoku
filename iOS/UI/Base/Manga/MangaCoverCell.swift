//
//  MangaCoverCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Kingfisher

class MangaCoverCell: UICollectionViewCell {

    var manga: Manga? {
        didSet {
            layoutViews()
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

    var imageView = UIImageView()
    var titleLabel = UILabel()
    var gradient = CAGradientLayer()
    var badgeView = UIView()
    var badgeLabel = UILabel()

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

        titleLabel.text = manga?.title ?? "No Title"
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

        highlightView.alpha = 0
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.layer.cornerRadius = layer.cornerRadius
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightView)

        overlayView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        overlayView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true

        activateConstraints()

        Task {
            await loadImage()
        }
    }

    func activateConstraints() {
        imageView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        imageView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true

        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true

        badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5).isActive = true
        badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5).isActive = true
        badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10).isActive = true
        badgeView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor).isActive = true
        badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor).isActive = true

        highlightView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        highlightView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
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
        let url = manga?.cover ?? ""

        let userAgentModifier: AnyModifier?

        if let sourceId = manga?.sourceId,
           let request = try? await SourceManager.shared.source(for: sourceId)?.getImageRequest(url: url) {
            userAgentModifier = AnyModifier { urlRequest in
                var r = urlRequest
                for (key, value) in request.headers {
                    r.setValue(value, forHTTPHeaderField: key)
                }
                if let body = request.body { r.httpBody = body }
                return r
            }
        } else {
            userAgentModifier = nil
        }

        // Run the image loading code immediately on the main actor
        await MainActor.run {
            let processor = DownsamplingImageProcessor(size: bounds.size) // |> RoundCornerImageProcessor(cornerRadius: 5)
            let retry = DelayRetryStrategy(maxRetryCount: 5, retryInterval: .seconds(0.5))
            var kfOptions: [KingfisherOptionsInfoItem] = [
                .processor(processor),
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(0.3)),
                .retryStrategy(retry),
                .cacheOriginalImage
            ]
            if let userAgentModifier = userAgentModifier {
                kfOptions.append(.requestModifier(userAgentModifier))
            }

            imageView.kf.setImage(
                with: URL(string: url),
                placeholder: UIImage(named: "MangaPlaceholder"),
                options: kfOptions
            ) { result in
                switch result {
                case .success(let value):
                    if self.manga?.tintColor == nil {
                        value.image.getColors(quality: .low) { colors in
                            let luma = colors?.background.luminance ?? 0
                            self.manga?.tintColor = luma >= 0.9 || luma <= 0.1 ? colors?.secondary : colors?.background
                        }
                    }
                default:
                    break
                }
            }
        }
    }
}

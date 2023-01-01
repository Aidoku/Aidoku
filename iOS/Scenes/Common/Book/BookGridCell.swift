//
//  BookGridCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/24/22.
//

import UIKit
import Nuke

class BookGridCell: UICollectionViewCell {

    var sourceId: String?
    var bookId: String?

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

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let overlayView = UIView()
    private let gradient = CAGradientLayer()
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private let bookmarkView = UIImageView()
    private let highlightView = UIView()

    private var imageTask: ImageTask?

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
    }

    func constrain() {
        imageView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        imageView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        imageView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        imageView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        overlayView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        overlayView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        overlayView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        overlayView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true

        badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5).isActive = true
        badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5).isActive = true
        badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10).isActive = true
        badgeView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor).isActive = true
        badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor).isActive = true

        bookmarkView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        bookmarkView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        bookmarkView.widthAnchor.constraint(equalToConstant: 17).isActive = true
        bookmarkView.heightAnchor.constraint(equalToConstant: 27).isActive = true

        highlightView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        highlightView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        highlightView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        highlightView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    override func layoutSubviews() {
        gradient.frame = bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = UIImage(named: "MangaPlaceholder")
    }

    func loadImage(url: URL?) async {
        guard let url = url else { return }

        if imageTask != nil {
            imageTask?.cancel()
            imageTask = nil
        }

        Task { @MainActor in
            imageView.image = UIImage(named: "MangaPlaceholder")
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

        do {
            let image = try await ImagePipeline.shared.image(for: request, delegate: self).image
            Task { @MainActor in
                UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve) {
                    self.imageView.image = image
                }
            }
        } catch {
            imageTask = nil
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
}

// MARK: - Nuke Delegate
extension BookGridCell: ImageTaskDelegate {

    func imageTaskCreated(_ task: ImageTask) {
        imageTask = task
    }
}

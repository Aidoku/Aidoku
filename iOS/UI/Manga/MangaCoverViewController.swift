//
//  MangaCoverViewController.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 01/07/2023.
//

import UIKit
import Nuke

class MangaCoverViewController: BaseViewController {

    private var manga: Manga

    // main stack view (containing everything)
    lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.distribution = .fillProportionally
        stackView.axis = .vertical
        stackView.backgroundColor = .systemBackground
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    let imageContainerView = UIView()

    // cover image
    private lazy var coverImageView: UIImageView = {
        let coverImageView = UIImageView()
        coverImageView.image = UIImage(named: "MangaPlaceholder")
        coverImageView.contentMode = .scaleAspectFit
        coverImageView.clipsToBounds = true
        coverImageView.layer.cornerRadius = 5
        coverImageView.layer.cornerCurve = .continuous
        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.isUserInteractionEnabled = true
        return coverImageView
    }()

    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?

    init(manga: Manga) {
        self.manga = manga
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func configure() {
        super.configure()

        navigationItem.largeTitleDisplayMode = .never
        navigationItem.title = NSLocalizedString("COVER", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(closePressed)
        )

        view.addSubview(stackView)
        stackView.addArrangedSubview(imageContainerView)

        coverImageView.addInteraction(UIContextMenuInteraction(delegate: self))

        imageContainerView.addSubview(coverImageView)

        imageWidthConstraint = coverImageView.widthAnchor.constraint(equalTo: imageContainerView.widthAnchor)
        imageWidthConstraint?.isActive = true

        Task {
            await setCover()
        }
    }

    override func constrain() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leftAnchor.constraint(equalTo: view.leftAnchor),
            stackView.rightAnchor.constraint(equalTo: view.rightAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            imageContainerView.topAnchor.constraint(equalTo: stackView.topAnchor, constant: 16),
            imageContainerView.leftAnchor.constraint(lessThanOrEqualTo: stackView.leftAnchor, constant: 16),
            imageContainerView.rightAnchor.constraint(equalTo: stackView.rightAnchor, constant: -16),
            imageContainerView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: -16),

            coverImageView.heightAnchor.constraint(lessThanOrEqualTo: imageContainerView.heightAnchor),
            coverImageView.widthAnchor.constraint(lessThanOrEqualTo: imageContainerView.widthAnchor),
            coverImageView.centerXAnchor.constraint(equalTo: imageContainerView.centerXAnchor),
            coverImageView.centerYAnchor.constraint(equalTo: imageContainerView.centerYAnchor)
        ])
    }

    private func setCover() async {
        Task { @MainActor in
            if coverImageView.image == nil {
                coverImageView.image = UIImage(named: "MangaPlaceholder")
            }
        }

        if let coverUrl = manga.coverUrl {
            var urlRequest = URLRequest(url: coverUrl)

            if
                let source = SourceManager.shared.source(for: manga.sourceId),
                source.handlesImageRequests,
                let request = try? await source.getImageRequest(url: coverUrl.absoluteString)
            {
                urlRequest.url = URL(string: request.URL ?? "")
                for (key, value) in request.headers {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }
                if let body = request.body { urlRequest.httpBody = body }
            }

            let request = ImageRequest(urlRequest: urlRequest)

            guard let image = try? await ImagePipeline.shared.image(for: request) else { return }
            Task { @MainActor in
                UIView.transition(with: coverImageView, duration: 0.3, options: .transitionCrossDissolve) {
                    self.coverImageView.image = image
                    self.fixImageSize()
                }
            }
        }
    }

    // match image constraints with image size
    func fixImageSize() {
        guard coverImageView.image != nil else { return }

        imageWidthConstraint?.isActive = false
        imageHeightConstraint?.isActive = false

        if
            case let height = coverImageView.image!.size.height * (imageContainerView.bounds.width / coverImageView.image!.size.width),
            height > imageContainerView.bounds.height
        {
            // max height, variable width
            let multiplier = coverImageView.image!.size.width / coverImageView.image!.size.height
            imageWidthConstraint = coverImageView.widthAnchor.constraint(
                equalTo: coverImageView.heightAnchor,
                multiplier: multiplier
            )
            imageHeightConstraint = coverImageView.heightAnchor.constraint(equalTo: imageContainerView.heightAnchor)
        } else {
            // max width, variable height
            let multiplier = coverImageView.image!.size.height / coverImageView.image!.size.width
            imageWidthConstraint = coverImageView.widthAnchor.constraint(equalTo: imageContainerView.widthAnchor)
            imageHeightConstraint = coverImageView.heightAnchor.constraint(
                equalTo: coverImageView.widthAnchor,
                multiplier: multiplier
            )
        }

        imageWidthConstraint?.isActive = true
        imageHeightConstraint?.isActive = true
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }
}

// MARK: - Context Menu Delegate
extension MangaCoverViewController: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
            let saveToPhotosAction = UIAction(
                title: NSLocalizedString("SAVE_TO_PHOTOS", comment: ""),
                image: UIImage(systemName: "photo")
            ) { _ in
                if let image = self?.coverImageView.image {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }

            let shareAction = UIAction(
                title: NSLocalizedString("SHARE", comment: ""),
                image: UIImage(systemName: "square.and.arrow.up")
            ) { _ in
                if let image = self?.coverImageView.image {
                    let items = [image]
                    let activityController = UIActivityViewController(activityItems: items, applicationActivities: nil)

                    activityController.popoverPresentationController?.sourceView = self?.view
                    activityController.popoverPresentationController?.sourceRect = CGRect(origin: location, size: .zero)

                    self?.present(activityController, animated: true)
                }
            }

            return UIMenu(title: "", children: [saveToPhotosAction, shareAction])
        })
    }
}

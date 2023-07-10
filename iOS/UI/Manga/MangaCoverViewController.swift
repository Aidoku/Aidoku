//
//  MangaCoverViewController.swift
//  Aidoku (iOS)
//
//  Created by axiel7 on 01/07/2023.
//

import UIKit
import Nuke

class MangaCoverViewController: BaseViewController {
    
    var coverUrl: URL
    
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
    
    init(coverUrl: URL) {
        self.coverUrl = coverUrl
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
        
        coverImageView.addInteraction(UIContextMenuInteraction(delegate: self))
        
        view.addSubview(stackView)
        stackView.addArrangedSubview(coverImageView)
        
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
            
            coverImageView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 16),
            coverImageView.leftAnchor.constraint(equalTo: stackView.leftAnchor, constant: 16),
            coverImageView.rightAnchor.constraint(equalTo: stackView.rightAnchor, constant: -16),
            coverImageView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: -16)
        ])
    }
    
    private func setCover() async {
        Task { @MainActor in
            if coverImageView.image == nil {
                coverImageView.image = UIImage(named: "MangaPlaceholder")
            }
        }

        let request = ImageRequest(urlRequest: URLRequest(url: coverUrl))

        guard let image = try? await ImagePipeline.shared.image(for: request).image else { return }
        Task { @MainActor in
            UIView.transition(with: coverImageView, duration: 0.3, options: .transitionCrossDissolve) {
                self.coverImageView.image = image
            }
        }
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
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { [weak self] _ in
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

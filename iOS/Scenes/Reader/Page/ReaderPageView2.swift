//
//  ReaderPageView2.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit
import Nuke
import NukeExtensions
import Kingfisher

class ReaderPageView2: UIView {

    private let imageView = UIImageView()
    private let progressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        progressView.trackColor = .quaternaryLabel
        progressView.progressColor = tintColor
        progressView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressView)

        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: 40),
            progressView.heightAnchor.constraint(equalToConstant: 40),
            progressView.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: centerYAnchor),

            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leftAnchor.constraint(equalTo: leftAnchor),
            imageView.rightAnchor.constraint(equalTo: rightAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func setPage(_ page: Page) {
        let request = ImageRequest(
            url: URL(string: page.imageURL!),
            processors: [.resize(width: UIScreen.main.bounds.width)]
        )

        NukeExtensions.loadImage(
            with: request,
            into: imageView,
            progress: { _, completed, total in
                self.progressView.setProgress(value: Float(completed) / Float(total), withAnimation: false)
            },
            completion: { _ in
                self.progressView.isHidden = true
            }
        )
    }
}

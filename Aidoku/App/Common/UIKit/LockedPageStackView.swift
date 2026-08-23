//
//  LockedPageStackView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/12/22.
//

import UIKit

class LockedPageStackView: UIStackView {

    var text: String? {
        get { textLabel.text }
        set { textLabel.text = newValue }
    }

    var buttonText: String? {
        get { button.title(for: .normal) }
        set { button.setTitle(newValue, for: .normal) }
    }

    private let imageView = UIImageView()
    private let textLabel = UILabel()
    let button = UIButton(type: .roundedRect)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        axis = .vertical
        alignment = .center
        distribution = .fill
        spacing = 2

        imageView.image = UIImage(systemName: "lock.fill")
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(imageView)
        setCustomSpacing(12, after: imageView)

        textLabel.font = .systemFont(ofSize: 16, weight: .medium)
        addArrangedSubview(textLabel)

        addArrangedSubview(button)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            imageView.heightAnchor.constraint(equalToConstant: 66),
            imageView.widthAnchor.constraint(equalToConstant: 66)
        ])
    }
}

//
//  IncognitoBannerView.swift
//  Aidoku
//
//  Created by Skitty on 12/15/25.
//

import UIKit

class IncognitoBannerView: UIView {
    private lazy var iconView: UIImageView = {
        let iconView = UIImageView()
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .caption1))
        iconView.image = UIImage(systemName: "eye.slash", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .label
        return iconView
    }()

    private lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.text = NSLocalizedString("INCOGNITO_MODE")
        textLabel.textColor = .label
        textLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        return textLabel
    }()

    private var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        return stackView
    }()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        backgroundColor = .init(dynamicProvider: { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? .systemGray3
                : .systemGray5
        })
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(textLabel)
        addSubview(stackView)
    }

    func constrain() {
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ])
    }
}

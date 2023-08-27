//
//  SourceInfoHeaderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/27/22.
//

import UIKit

class SourceInfoHeaderView: UIView {

    var source: Source

    let iconSize: CGFloat = 48

    let contentView = UIView()
    let iconView = UIImageView()
    let labelStack = UIStackView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let uninstallButton = UIButton(type: .roundedRect)

    init(source: Source) {
        self.source = source
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        let iconUrl = source.url.appendingPathComponent("Icon.png")
        let path: String
        if #available(iOS 16.0, *) {
            path = iconUrl.path()
        } else {
            path = iconUrl.path
        }
        iconView.image = UIImage(contentsOfFile: path)
        iconView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        iconView.layer.borderWidth = 1
        iconView.layer.cornerRadius = iconSize * 0.225
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        labelStack.axis = .vertical
        labelStack.distribution = .equalSpacing
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelStack)

        titleLabel.text = source.manifest.info.name
        labelStack.addArrangedSubview(titleLabel)

        subtitleLabel.text = source.id
        subtitleLabel.textColor = .secondaryLabel
        labelStack.addArrangedSubview(subtitleLabel)

//        uninstallButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
//        uninstallButton.setTitle("UNINSTALL", for: .normal)
//        uninstallButton.setTitleColor(.white, for: .normal)
//        uninstallButton.layer.cornerRadius = 14
//        uninstallButton.backgroundColor = tintColor
        uninstallButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(uninstallButton)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            uninstallButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            uninstallButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            uninstallButton.widthAnchor.constraint(equalToConstant: uninstallButton.intrinsicContentSize.width + 24),
            uninstallButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
}

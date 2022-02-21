//
//  ExternalSourceTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Kingfisher

class ExternalSourceTableViewCell: UITableViewCell {

    var source: ExternalSourceInfo? {
        didSet {
            loadInfo()
        }
    }

    let sourceURL: String

    let iconView = UIImageView()
    let titleLabel = UILabel()
    let versionLabel = UILabel()
    let subtitleLabel = UILabel()
    let getButton = GetButtonView()

    var buttonWidth: CGFloat = 67 {
        didSet {
            getButtonWidthConstraint?.constant = buttonWidth
        }
    }

    var getButtonWidthConstraint: NSLayoutConstraint?

    init(reuseIdentifier: String?, sourceURL: String) {
        self.sourceURL = sourceURL
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    init(style: UITableViewCell.CellStyle, reuseIdentifier: String?, sourceURL: String) {
        self.sourceURL = sourceURL
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupViews() {
        backgroundColor = .clear

        selectionStyle = .none

        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = 48 * 0.225
        iconView.layer.cornerCurve = .continuous
        iconView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        iconView.layer.borderWidth = 1
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        let labelStack = UIStackView()
        labelStack.distribution = .equalSpacing
        labelStack.axis = .vertical
        labelStack.spacing = 1
        labelStack.alignment = .leading
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelStack)

        let titleStack = UIStackView()
        titleStack.distribution = .equalSpacing
        titleStack.axis = .horizontal
        titleStack.spacing = 6
        labelStack.addArrangedSubview(titleStack)

        titleLabel.font = UIFont.systemFont(ofSize: 16)
        titleStack.addArrangedSubview(titleLabel)

        versionLabel.font = titleLabel.font
        versionLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(versionLabel)

        subtitleLabel.font = titleLabel.font
        subtitleLabel.textColor = .secondaryLabel
        labelStack.addArrangedSubview(subtitleLabel)

        getButton.button.addTarget(self, action: #selector(getPressed), for: .touchUpInside)
        getButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(getButton)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10).isActive = true
        labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        getButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        getButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        getButtonWidthConstraint = getButton.widthAnchor.constraint(equalToConstant: buttonWidth)
        getButtonWidthConstraint?.isActive = true
        getButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        separator.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }

    func loadInfo() {
        titleLabel.text = source?.name
        versionLabel.text = "v\(source?.version ?? 1)"
        subtitleLabel.text = source?.id
        iconView.kf.setImage(
            with: URL(string: "\(sourceURL)/icons/\(source?.icon ??  "")"),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: nil
        )
    }

    @objc func getPressed() {
        Task {
            getButton.buttonState = .downloading
            let installedSource = await SourceManager.shared.importSource(
                from: URL(string: "\(sourceURL)/sources/\(source?.file ?? "")")!
            )
            getButton.buttonState = installedSource == nil ? .fail : .get
        }
    }
}

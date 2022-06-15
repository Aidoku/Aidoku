//
//  SourceTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Kingfisher

class SourceTableViewCell: UITableViewCell {

    var source: Source? {
        didSet {
            loadInfo()
        }
    }

    let iconView = UIImageView()
    let titleLabel = UILabel()
    let versionLabel = UILabel()
    let badgeView = UIView()
    let badgeLabel = UILabel()
    let subtitleLabel = UILabel()

    init(reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupViews() {
        backgroundColor = .clear
        accessoryType = .disclosureIndicator

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
        titleStack.distribution = .fill
        titleStack.axis = .horizontal
        titleStack.spacing = 5
        labelStack.addArrangedSubview(titleStack)

        titleLabel.font = UIFont.systemFont(ofSize: 16)
        titleStack.addArrangedSubview(titleLabel)

        versionLabel.font = titleLabel.font
        versionLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(versionLabel)

        badgeView.backgroundColor = .systemRed.withAlphaComponent(0.3)
        badgeView.layer.cornerRadius = 6
        badgeView.layer.cornerCurve = .continuous

        badgeLabel.text = "18+"
        badgeLabel.textColor = .secondaryLabel
        badgeLabel.font = .systemFont(ofSize: 10)
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)
        titleStack.addArrangedSubview(badgeView)

        subtitleLabel.font = titleLabel.font
        subtitleLabel.textColor = .secondaryLabel
        labelStack.addArrangedSubview(subtitleLabel)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true

        labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12).isActive = true
        labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor).isActive = true
        badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor).isActive = true
        badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10).isActive = true
        badgeView.heightAnchor.constraint(equalTo: badgeLabel.heightAnchor, constant: 4).isActive = true

        separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        separator.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }

    func loadInfo() {
        titleLabel.text = source?.manifest.info.name
        versionLabel.text = "v\(source?.manifest.info.version ?? 1)"
        badgeView.isHidden = source?.manifest.info.nsfw ?? 0 <= 1
        subtitleLabel.text = source?.manifest.info.lang == "multi" ? NSLocalizedString("MULTI_LANGUAGE", comment: "")
            : (Locale.current as NSLocale).displayName(forKey: .identifier, value: source?.manifest.info.lang ?? "")
        iconView.kf.setImage(
            with: source?.url.appendingPathComponent("Icon.png"),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: nil
        )
    }
}

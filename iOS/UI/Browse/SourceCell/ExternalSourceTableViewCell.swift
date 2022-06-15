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

    let iconView = UIImageView()
    let titleLabel = UILabel()
    let versionLabel = UILabel()
    let badgeView = UIView()
    let badgeLabel = UILabel()
    let subtitleLabel = UILabel()
    let getButton = GetButtonView()

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
        titleStack.distribution = .fill
        titleStack.axis = .horizontal
        titleStack.spacing = 5
        labelStack.addArrangedSubview(titleStack)

        titleLabel.font = UIFont.systemFont(ofSize: 16)
        titleStack.addArrangedSubview(titleLabel)

        versionLabel.font = titleLabel.font
        versionLabel.textColor = .secondaryLabel
        titleStack.addArrangedSubview(versionLabel)
        titleStack.setCustomSpacing(8, after: versionLabel)

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

        labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12).isActive = true
        labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor).isActive = true
        badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor).isActive = true
        badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10).isActive = true
        badgeView.heightAnchor.constraint(equalTo: badgeLabel.heightAnchor, constant: 4).isActive = true

        getButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        getButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        getButton.widthAnchor.constraint(equalTo: getButton.backgroundView.widthAnchor).isActive = true
        getButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        separator.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    }

    func loadInfo() {
        titleLabel.text = source?.name
        versionLabel.text = "v\(source?.version ?? 1)"
        badgeView.isHidden = source?.nsfw ?? 0 <= 1
        subtitleLabel.text = source?.lang == "multi" ? NSLocalizedString("MULTI_LANGUAGE", comment: "")
            : (Locale.current as NSLocale).displayName(forKey: .identifier, value: source?.lang ?? "")
        iconView.kf.setImage(
            with: source?.sourceUrl?.appendingPathComponent("icons", isDirectory: true).appendingPathComponent(source?.icon ??  ""),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: nil
        )
    }

    @objc func getPressed() {
        if let url = source?.sourceUrl {
            getButton.buttonState = .downloading
            Task {
                let installedSource = await SourceManager.shared.importSource(
                    from: url.appendingPathComponent("sources", isDirectory: true).appendingPathComponent(source?.file ??  "")
                )
                getButton.buttonState = installedSource == nil ? .fail : .get
            }
        }
    }
}

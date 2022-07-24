//
//  TrackerSearchTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 7/21/22.
//

import UIKit

class TrackerSearchTableViewCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let typeLabel = UILabel()
    private let statusLabel = UILabel()
//    private let descriptionLabel = UILabel() // TODO

    var item: TrackSearchItem? {
        didSet {
            updateInfo()
        }
    }

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
        guard let imageView = imageView else { return }
        backgroundColor = .clear

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 5
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let labelStack = UIStackView()
        labelStack.distribution = .fill
        labelStack.axis = .vertical
        labelStack.spacing = 4
        labelStack.alignment = .leading
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelStack)

        titleLabel.font = UIFont.systemFont(ofSize: 16)
        titleLabel.numberOfLines = 2
        labelStack.addArrangedSubview(titleLabel)

        typeLabel.font = UIFont.systemFont(ofSize: 14)
        typeLabel.textColor = .secondaryLabel
        typeLabel.numberOfLines = 1
        labelStack.addArrangedSubview(typeLabel)

        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 1
        labelStack.addArrangedSubview(statusLabel)

        imageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 56 * 3/2).isActive = true

        labelStack.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12).isActive = true
        labelStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        separator.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        separator.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        contentView.heightAnchor.constraint(equalToConstant: 100).isActive = true
    }

    func updateInfo() {
        imageView?.kf.setImage(
            with: URL(string: item?.coverUrl ?? ""),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: [
                .transition(.fade(0.2))
            ]
        )
        titleLabel.text = item?.title ?? ""
        if item?.type != .unknown, let type = item?.type?.toString() {
            typeLabel.text = String(format: NSLocalizedString("TYPE_COLON_%@", comment: ""), type)
        }
        if item?.status != .unknown, let status = item?.status?.toString() {
            statusLabel.text = String(format: NSLocalizedString("STATUS_COLON_%@", comment: ""), status)
        }
    }
}

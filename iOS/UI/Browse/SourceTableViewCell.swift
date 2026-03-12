//
//  SourceTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Nuke

protocol SourceCellDelegate: AnyObject {
    func getButtonPressed(cell: SourceTableViewCell)
    func warningButtonPressed(cell: SourceTableViewCell)
}

class SourceTableViewCell: UITableViewCell {
    var info: SourceInfo2?
    weak var delegate: SourceCellDelegate?

    private var iconSize: CGFloat = 48 {
        didSet {
            iconView.layer.cornerRadius = iconSize * 0.225
        }
    }

    private let labelStack = UIStackView()
    private let titleStack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let versionLabel = UILabel()
    private let badgeView = UIView()
    private let badgeLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separator = UIView()
    private let warningButton = UIButton()
    let getButton = GetButtonView()

    private var imageTask: ImageTask?

    var buttonTitle: String? {
        get {
            getButton.title
        }
        set {
            getButton.title = newValue
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        // TODO: use contentConfiguration
        backgroundColor = .systemBackground
        accessoryType = .disclosureIndicator

        iconView.image = UIImage(named: "MangaPlaceholder")
        iconView.clipsToBounds = true
        iconView.layer.cornerRadius = iconSize * 0.225
        iconView.layer.cornerCurve = .continuous
        iconView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        iconView.layer.borderWidth = 1
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        labelStack.distribution = .equalSpacing
        labelStack.axis = .vertical
        labelStack.spacing = 1
        labelStack.alignment = .leading
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelStack)

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

        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = UIImage(systemName: "exclamationmark.triangle", withConfiguration: config)
        warningButton.setImage(image, for: .normal)
        warningButton.addTarget(self, action: #selector(warningPressed), for: .touchUpInside)
        warningButton.tintColor = .systemGray3
        warningButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(warningButton)

        getButton.button.addTarget(self, action: #selector(getPressed), for: .touchUpInside)
        getButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(getButton)

        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),

            labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10),
            badgeView.heightAnchor.constraint(equalTo: badgeLabel.heightAnchor, constant: 4),

            warningButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -6),
            warningButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            getButton.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            getButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            getButton.widthAnchor.constraint(equalTo: getButton.backgroundView.widthAnchor),
            getButton.heightAnchor.constraint(equalToConstant: 28),

            separator.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            contentView.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        info = nil
        iconView.image = UIImage(named: "MangaPlaceholder")
    }

    func setSourceInfo(_ info: SourceInfo2, showButton: Bool = false) {
        self.info = info
        titleLabel.text = info.name
        versionLabel.text = "v" + String(info.version)
        badgeView.isHidden = info.contentRating != .primarilyNsfw
        subtitleLabel.text = info.isMultiLanguage
            ? NSLocalizedString("MULTI_LANGUAGE")
            : Locale.current.localizedString(forIdentifier: info.languages[0]) ?? info.languages[0]

        warningButton.isHidden = !info.external || info.externalInfo != nil
        getButton.isHidden = !showButton

        // load icon
        if let iconUrl = info.iconUrl {
            Task {
                await loadIcon(url: iconUrl)
            }
        } else {
            switch info.sourceId {
                case LocalSourceRunner.sourceKey:
                    iconView.image = UIImage.local
                case let x where x.hasPrefix(KomgaSourceRunner.sourceKeyPrefix):
                    iconView.image = UIImage.komga
                case let x where x.hasPrefix(KavitaSourceRunner.sourceKeyPrefix):
                    iconView.image = UIImage.kavita
                default:
                    break
            }
        }
    }

    private func loadIcon(url: URL) async {
        if imageTask != nil {
            imageTask?.cancel()
            imageTask = nil
        }
        let request = ImageRequest(
            url: url,
            processors: [DownsampleProcessor(width: bounds.width)]
        )
        let wasCached = ImagePipeline.shared.cache.containsCachedImage(for: request)

        imageTask = ImagePipeline.shared.loadImage(with: request) { [weak self] result in
            guard let self else { return }
            switch result {
                case .success(let response):
                    Task { @MainActor in
                        if wasCached {
                            self.iconView.image = response.image
                        } else {
                            UIView.transition(with: self.iconView, duration: 0.3, options: .transitionCrossDissolve) {
                                self.iconView.image = response.image
                            }
                        }
                    }
                case .failure:
                    imageTask = nil
            }
        }
    }

    @objc func getPressed() {
        delegate?.getButtonPressed(cell: self)
    }

    @objc func warningPressed() {
        delegate?.warningButtonPressed(cell: self)
    }
}

//
//  HistoryTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/2/22.
//

import UIKit
import Nuke

class HistoryTableViewCell: UITableViewCell {

    let titleLabel = UILabel()
    let subtitleLabel = UILabel()

    var entry: HistoryEntry? {
        didSet {
            updateInfo()
        }
    }

    init(reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        configure()
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView?.image = UIImage(named: "MangaPlaceholder")
    }

    func configure() {
        guard let imageView = imageView else { return }
        backgroundColor = .clear

        imageView.image = UIImage(named: "MangaPlaceholder")
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

        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        labelStack.addArrangedSubview(subtitleLabel)

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
        titleLabel.text = entry?.manga.title ?? ""
        var subtitleText = ""
        if entry?.chapter.chapterNum ?? -1 >= 0 {
            subtitleText += String(format: NSLocalizedString("CH_SPACE_X", comment: ""), entry?.chapter.chapterNum ?? 0)
        }
        if let currentPage = entry?.currentPage, let totalPages = entry?.totalPages, currentPage > 0, currentPage < totalPages {
            subtitleText += " - " + String(format: NSLocalizedString("PAGE_X_OF_X", comment: ""), currentPage, totalPages)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        subtitleText += " - " + formatter.string(from: entry?.date ?? Date())
        subtitleLabel.text = subtitleText

        Task {
            await loadCoverImage()
        }
    }

    func loadCoverImage() async {
        guard
            let imageView = imageView,
            let url = entry?.manga.coverUrl
        else { return }

        let request = ImageRequest(url: url, processors: [DownsampleProcessor(size: bounds.size)])
        if let image = try? await ImagePipeline.shared.image(for: request) {
            Task { @MainActor in
                UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve) {
                    imageView.image = image
                }
            }
        }
    }
}

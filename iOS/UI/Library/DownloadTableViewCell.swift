//
//  DownloadTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/22/22.
//

import UIKit

class DownloadTableViewCell: UITableViewCell {

    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let progressView = UIProgressView()
    let progressLabel = UILabel()

    var progress: Int = 0 {
        didSet {
            updateProgress()
        }
    }
    var total: Int = 0 {
        didSet {
            updateProgress()
        }
    }

    override init(style: UITableViewCell.CellStyle = .default, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureProgressView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureProgressView() {
        let labelStack = UIStackView()
        labelStack.distribution = .fill
        labelStack.axis = .vertical
        labelStack.spacing = 4
        labelStack.alignment = .leading
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelStack)

        titleLabel.font = UIFont.systemFont(ofSize: 16)
        labelStack.addArrangedSubview(titleLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        labelStack.addArrangedSubview(subtitleLabel)
        labelStack.setCustomSpacing(10, after: subtitleLabel)

        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        labelStack.addArrangedSubview(progressView)
        progressView.widthAnchor.constraint(equalTo: labelStack.widthAnchor).isActive = true

        progressLabel.font = UIFont.systemFont(ofSize: 13)
        progressLabel.textColor = .secondaryLabel
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressLabel)

        labelStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        labelStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        progressLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor).isActive = true
        progressLabel.trailingAnchor.constraint(equalTo: labelStack.trailingAnchor).isActive = true

        contentView.heightAnchor.constraint(equalToConstant: 80).isActive = true
    }

    @MainActor
    func updateProgress() {
        if total > 0 {
            progressView.isHidden = false
            progressLabel.text = "\(progress)/\(total)"
            progressView.progress = Float(progress) / Float(total)
        } else {
            progressView.isHidden = true
            progressLabel.text = nil
            progressView.progress = 0
        }
    }
}

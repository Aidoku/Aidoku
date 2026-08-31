//
//  StepperTableViewCell.swift
//  Aidoku
//
//  Created by Skitty on 7/30/25.
//

import UIKit

class StepperTableViewCell: UITableViewCell {
    let titleLabel = UILabel()
    let detailLabel = UILabel()
    let stepperView = UIStepper()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        textLabel?.isHidden = true

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail

        detailLabel.textColor = .secondaryLabel
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        detailLabel.lineBreakMode = .byClipping

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        accessoryView = stepperView
        selectionStyle = .none

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

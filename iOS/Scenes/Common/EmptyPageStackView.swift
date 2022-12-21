//
//  EmptyPageStackView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/12/22.
//

import UIKit

class EmptyPageStackView: UIStackView {

    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    var text: String? {
        get { textLabel.text }
        set { textLabel.text = newValue }
    }

    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    // TODO: optional button

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        axis = .vertical
        alignment = .center
        distribution = .equalSpacing
        spacing = 5

        titleLabel.font = .systemFont(ofSize: 25, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        addArrangedSubview(titleLabel)

        textLabel.font = .systemFont(ofSize: 15)
        textLabel.textColor = .secondaryLabel
        addArrangedSubview(textLabel)
    }
}

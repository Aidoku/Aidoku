//
//  SmallSectionHeaderConfiguration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/31/22.
//

import UIKit

struct SmallSectionHeaderConfiguration: UIContentConfiguration {

    var title: String?

    func makeContentView() -> UIView & UIContentView {
        SmallSectionHeaderContentView(self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

class SmallSectionHeaderContentView: UIView, UIContentView {

    var configuration: UIContentConfiguration {
        didSet {
            configure()
        }
    }

    let titleLabel = UILabel()

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor, constant: -12)
        ])

        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        guard let configuration = configuration as? SmallSectionHeaderConfiguration else { return }
        titleLabel.text = configuration.title
    }
}

//
//  MangaLabelView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/2/23.
//

import UIKit

class MangaLabelView: UIView {

    private let padding: CGFloat = 8

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    lazy var label: UILabel = {
        let label = UILabel()
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 10)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous

        addSubview(label)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            widthAnchor.constraint(equalTo: label.widthAnchor, constant: padding * 2),
            heightAnchor.constraint(equalTo: label.heightAnchor, constant: padding)
        ])
    }
}

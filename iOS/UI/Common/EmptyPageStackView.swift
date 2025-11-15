//
//  EmptyPageStackView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/12/22.
//

import UIKit

class EmptyPageStackView: UIStackView {
    var imageSystemName: String? {
        didSet {
            if let imageSystemName {
                let config = UIImage.SymbolConfiguration(pointSize: 48, weight: .regular)
                imageView.image = UIImage(systemName: imageSystemName, withConfiguration: config)
                imageView.isHidden = false
            } else {
                imageView.isHidden = true
            }
        }
    }

    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    var text: String? {
        get { textLabel.text }
        set { textLabel.text = newValue }
    }

    var buttonText: String? {
        get { button.title(for: .normal) }
        set { button.setTitle(newValue, for: .normal) }
    }

    var showsButton: Bool {
        get { !button.isHidden }
        set { button.isHidden = !newValue }
    }

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let textLabel = UILabel()
    private let button = UIButton(type: .roundedRect)

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
        spacing = 4

        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        addArrangedSubview(imageView)
        setCustomSpacing(16, after: imageView)

        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title2).bold()
        titleLabel.textColor = .label
        addArrangedSubview(titleLabel)

        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.font = UIFont.preferredFont(forTextStyle: .callout)
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        addArrangedSubview(textLabel)

        button.isHidden = true
        addArrangedSubview(button)
    }

    func addButtonTarget(_ target: Any?, action: Selector, for event: UIControl.Event = .touchUpInside) {
        button.addTarget(target, action: action, for: event)
    }
}

private extension UIFont {
    func bold() -> UIFont {
        if let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) {
            UIFont(descriptor: descriptor, size: pointSize)
        } else {
            self
        }
    }
}

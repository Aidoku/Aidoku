//
//  ExpandableTextView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/2/22.
//

import UIKit

class ExpandableTextView: UIView {

    weak var sizeChangeListener: SizeChangeListenerDelegate?

    var text: String? {
        get {
            textLabel.text
        }
        set {
            textLabel.text = newValue
            invalidateIntrinsicContentSize()
        }
    }
    var expanded = false {
        didSet {
            if expanded {
                UIView.transition(with: self, duration: 0.3, options: .transitionCrossDissolve) {
                    self.textLabel.numberOfLines = 0
                    self.invalidateIntrinsicContentSize()
//                    self.host?.view.setNeedsLayout()
                    self.moreButton.alpha = 0
                    self.fadeView.alpha = 0
                    self.sizeChangeListener?.sizeChanged(self.bounds.size)
                }
            } else {
                textLabel.numberOfLines = 4
                invalidateIntrinsicContentSize()
                self.sizeChangeListener?.sizeChanged(self.bounds.size)
                moreButton.alpha = 1
                fadeView.alpha = 1
            }
        }
    }

    let textLabel = UILabel()
    let moreButton = UIButton(type: .roundedRect)
    let fadeView = UIView()
    let fadeGradient = CAGradientLayer()

    override var intrinsicContentSize: CGSize {
        textLabel.intrinsicContentSize
    }

    init() {
        super.init(frame: .zero)
        configureLabel()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureLabel() {
        textLabel.textColor = .secondaryLabel
        textLabel.font = .systemFont(ofSize: 15)
        textLabel.numberOfLines = 4
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        moreButton.setTitle(NSLocalizedString("MORE", comment: "Description expansion button"), for: .normal)
        moreButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        moreButton.backgroundColor = .systemBackground
        moreButton.titleLabel?.font = .systemFont(ofSize: 12)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(moreButton)

        fadeGradient.frame = CGRect(x: 0, y: 0, width: 20, height: 18)
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            fadeGradient.startPoint = CGPoint(x: 1, y: 0.5)
            fadeGradient.endPoint = CGPoint(x: 0, y: 0.5)
        } else {
            fadeGradient.startPoint = CGPoint(x: 0, y: 0.5)
            fadeGradient.endPoint = CGPoint(x: 1, y: 0.5)
        }
        fadeGradient.locations = [0, 1]
        fadeGradient.colors = [
            UIColor.systemBackground.withAlphaComponent(0).cgColor,
            UIColor.systemBackground.cgColor
        ]
        fadeView.layer.insertSublayer(fadeGradient, at: 0)
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fadeView)

        textLabel.topAnchor.constraint(equalTo: topAnchor).isActive = true
        textLabel.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        moreButton.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor).isActive = true
        moreButton.bottomAnchor.constraint(equalTo: textLabel.bottomAnchor).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 18).isActive = true

        fadeView.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor).isActive = true
        fadeView.bottomAnchor.constraint(equalTo: moreButton.bottomAnchor).isActive = true
        fadeView.heightAnchor.constraint(equalTo: moreButton.heightAnchor).isActive = true
        fadeView.widthAnchor.constraint(equalToConstant: 20).isActive = true

        heightAnchor.constraint(equalTo: textLabel.heightAnchor).isActive = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            fadeGradient.colors = [
                UIColor.systemBackground.withAlphaComponent(0).cgColor,
                UIColor.systemBackground.cgColor
            ]
            setNeedsDisplay()
        }
    }

    @objc func toggleExpanded() {
        expanded.toggle()
    }
}

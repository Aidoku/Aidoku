//
//  DoubleBadgeView.swift
//  Aidoku
//
//  Created by Skitty on 11/21/25.
//

import UIKit

class DoubleBadgeView: UIView {
    var badgeNumber: Int {
        get {
            Int(badgeLabel.text ?? "") ?? 0
        }
        set {
            badgeLabel.text = newValue == 0 ? nil : String(newValue)
            badgeView.isHidden = badgeLabel.text == nil
            updateLayout()
        }
    }

    var badgeNumber2: Int {
        get {
            Int(badgeLabel2.text ?? "") ?? 0
        }
        set {
            badgeLabel2.text = newValue == 0 ? nil : String(newValue)
            badgeView2.isHidden = badgeLabel2.text == nil
            updateLayout()
        }
    }

    private lazy var badgeView = {
        let badgeView = UIView()
        badgeView.isHidden = true
        badgeView.backgroundColor = tintColor
        badgeView.layer.cornerRadius = 5
        badgeView.addSubview(badgeLabel)
        return badgeView
    }()

    private let badgeLabel = {
        let badgeLabel = UILabel()
        badgeLabel.textColor = .white
        badgeLabel.numberOfLines = 1
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        return badgeLabel
    }()

    private lazy var badgeView2 = {
        let badgeView = UIView()
        badgeView.isHidden = true
        badgeView.backgroundColor = .systemIndigo
        badgeView.layer.cornerRadius = 5
        badgeView.addSubview(badgeLabel2)
        return badgeView
    }()

    private let badgeLabel2 = {
        let badgeLabel = UILabel()
        badgeLabel.textColor = .white
        badgeLabel.numberOfLines = 1
        badgeLabel.font = .systemFont(ofSize: 13, weight: .medium)
        return badgeLabel
    }()

    private var badgeConstraints: [NSLayoutConstraint] = []

    override var intrinsicContentSize: CGSize {
        layoutIfNeeded()

        var width: CGFloat = 0
        var height: CGFloat = 0

        if !badgeView.isHidden {
            width += badgeView.frame.width
            height = max(height, badgeView.frame.height)
        }
        if !badgeView2.isHidden {
            width += badgeView2.frame.width
            height = max(height, badgeView2.frame.height)
        }

        return CGSize(width: width, height: height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        addSubview(badgeView)
        addSubview(badgeView2)
    }

    func constrain() {
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView2.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel2.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeLabel2.setContentHuggingPriority(.required, for: .horizontal)
        badgeLabel2.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            badgeView.widthAnchor.constraint(equalTo: badgeLabel.widthAnchor, constant: 10),
            badgeView.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            badgeView2.widthAnchor.constraint(equalTo: badgeLabel2.widthAnchor, constant: 10),
            badgeView2.heightAnchor.constraint(equalToConstant: 20),
            badgeLabel2.centerXAnchor.constraint(equalTo: badgeView2.centerXAnchor),
            badgeLabel2.centerYAnchor.constraint(equalTo: badgeView2.centerYAnchor)
        ])

        updateLayout()
    }

    override func tintColorDidChange() {
        badgeView.backgroundColor = tintColor
        if tintAdjustmentMode == .dimmed {
            badgeView2.backgroundColor = .systemIndigo.grayscale()
        } else {
            badgeView2.backgroundColor = .systemIndigo
        }
    }

    func updateLayout() {
        NSLayoutConstraint.deactivate(badgeConstraints)
        if badgeNumber > 0 && badgeNumber2 > 0 {
            // both badges visible, show side by side
            badgeView.isHidden = false
            badgeView2.isHidden = false
            badgeView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner] // top-left, bottom-left
            badgeView2.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner] // top-right, bottom-right
            badgeConstraints = [
                badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
                badgeView2.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor),
                badgeView2.topAnchor.constraint(equalTo: badgeView.topAnchor)
            ]
            NSLayoutConstraint.activate(badgeConstraints)
        } else if badgeNumber > 0 {
            // only first badge visible
            badgeView.isHidden = false
            badgeView2.isHidden = true
            badgeView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            badgeConstraints = [
                badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                badgeView.topAnchor.constraint(equalTo: topAnchor, constant: 5)
            ]
            NSLayoutConstraint.activate(badgeConstraints)
        } else if badgeNumber2 > 0 {
            // only second badge visible
            badgeView.isHidden = true
            badgeView2.isHidden = false
            badgeView2.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            badgeConstraints = [
                badgeView2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
                badgeView2.topAnchor.constraint(equalTo: topAnchor, constant: 5)
            ]
            NSLayoutConstraint.activate(badgeConstraints)
        } else {
            badgeView.isHidden = true
            badgeView2.isHidden = true
        }
        self.invalidateIntrinsicContentSize()
    }
}

private extension UIColor {
    /// Returns a grayscale version of the color.
    func grayscale() -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }

        let gray = red * 0.299 + green * 0.587 + blue * 0.114
        return UIColor(red: gray, green: gray, blue: gray, alpha: alpha)
    }
}

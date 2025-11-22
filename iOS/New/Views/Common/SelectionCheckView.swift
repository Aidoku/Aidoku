//
//  SelectionCheckView.swift
//  Aidoku
//
//  Created by Skitty on 11/21/25.
//

import UIKit

class SelectionCheckView: UIView {
    private lazy var unselectedView = {
        let view = UIView()
        view.layer.cornerRadius = frame.width / 2
        view.layer.borderColor = UIColor.systemGray3.cgColor
        view.layer.borderWidth = 1.5
        return view
    }()

    private lazy var selectedView = {
        let view = UIView()
        view.layer.cornerRadius = frame.width / 2
        view.backgroundColor = tintColor
        return view
    }()

    private lazy var checkmarkImageView: UIImageView = {
        let checkmarkImageView = UIImageView()
        checkmarkImageView.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)
        )
        checkmarkImageView.tintColor = .white
        checkmarkImageView.contentMode = .scaleAspectFit
        if #available(iOS 26.0, *) {
            // fix initial animation not working
            checkmarkImageView.addSymbolEffect(.disappear, animated: false)
        }
        return checkmarkImageView
    }()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        selectedView.isHidden = true
        checkmarkImageView.isHidden = true

        addSubview(unselectedView)
        addSubview(selectedView)
        addSubview(checkmarkImageView)
    }

    func constrain() {
        unselectedView.translatesAutoresizingMaskIntoConstraints = false
        selectedView.translatesAutoresizingMaskIntoConstraints = false
        checkmarkImageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            unselectedView.topAnchor.constraint(equalTo: topAnchor),
            unselectedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            unselectedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            unselectedView.trailingAnchor.constraint(equalTo: trailingAnchor),

            selectedView.topAnchor.constraint(equalTo: topAnchor),
            selectedView.bottomAnchor.constraint(equalTo: bottomAnchor),
            selectedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectedView.trailingAnchor.constraint(equalTo: trailingAnchor),

            checkmarkImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmarkImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmarkImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 2/3),
            checkmarkImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 2/3)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        unselectedView.layer.borderColor = UIColor.systemGray3.resolvedColor(with: traitCollection).cgColor
    }

    func setSelected(_ selected: Bool, animated: Bool = true) {
        if selected {
            if #available(iOS 26.0, *) {
                selectedView.layer.removeAllAnimations()
                selectedView.alpha = 1

                checkmarkImageView.addSymbolEffect(.drawOn, animated: animated)
            }
            checkmarkImageView.isHidden = false
            selectedView.isHidden = false
        } else if !checkmarkImageView.isHidden {
            if #available(iOS 26.0, *) {
                checkmarkImageView.addSymbolEffect(.disappear, animated: animated)

                if animated {
                    selectedView.layer.removeAllAnimations()

                    UIView.animate(withDuration: CATransaction.animationDuration() / 2) {
                        self.selectedView.alpha = 0
                    } completion: { finished in
                        if finished {
                            self.checkmarkImageView.isHidden = true
                            self.selectedView.isHidden = true
                            self.selectedView.alpha = 1
                        }
                    }
                } else {
                    self.checkmarkImageView.isHidden = true
                    self.selectedView.isHidden = true
                    self.selectedView.alpha = 1
                }
            } else {
                checkmarkImageView.isHidden = true
                selectedView.isHidden = true
            }
        }
    }
}

//
//  GetButtonView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit

class GetButtonView: UIView {

    enum State {
        case get
        case downloading
        case fail
    }

    var buttonState: State = .get {
        didSet {
            if buttonState == .downloading {
                UIView.animate(withDuration: 0.3) {
                    self.button.setTitle("", for: .normal)
                    self.activityIndicator.startAnimating()

                    self.widthConstraint?.isActive = false
                    self.widthConstraint = self.backgroundView.widthAnchor.constraint(equalToConstant: 28)
                    self.widthConstraint?.isActive = true
                }
            } else {
                UIView.animate(withDuration: 0.3) {
                    self.button.setTitle(self.buttonState == .fail ? NSLocalizedString("BUTTON_ERROR", comment: "") : self.title, for: .normal)
                    self.calculatePadding()
                    self.activityIndicator.stopAnimating()

                    self.widthConstraint?.isActive = false
                    self.widthConstraint = self.backgroundView.widthAnchor.constraint(equalTo: self.button.widthAnchor, constant: self.sidePadding)
                    self.widthConstraint?.isActive = true
                }
            }
        }
    }

    var title: String? = NSLocalizedString("BUTTON_GET", comment: "") {
        didSet {
            button.setTitle(title, for: .normal)
            calculatePadding()
        }
    }

    var sidePadding: CGFloat = 16

    let backgroundView = UIView()
    let activityIndicator = UIActivityIndicatorView()
    let button = UIButton()
    var widthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundView.clipsToBounds = true
        backgroundView.backgroundColor = .tertiarySystemFill
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)

        activityIndicator.hidesWhenStopped = true
        activityIndicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)

        button.setTitle(title, for: .normal)
        button.setTitleColor(tintColor, for: .normal)

        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)

        button.addTarget(self, action: #selector(touchDown), for: .touchDown)
        button.addTarget(self, action: #selector(touchUp), for: .touchDragExit)
        button.addTarget(self, action: #selector(touchUp), for: .touchCancel)
        button.addTarget(self, action: #selector(touchUp), for: .touchUpInside)

        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        backgroundView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        backgroundView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        widthConstraint = backgroundView.widthAnchor.constraint(equalTo: button.widthAnchor, constant: sidePadding)
        widthConstraint?.isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        activityIndicator.centerYAnchor.constraint(equalTo: button.centerYAnchor).isActive = true
        activityIndicator.centerXAnchor.constraint(equalTo: button.centerXAnchor).isActive = true

        button.topAnchor.constraint(equalTo: topAnchor).isActive = true
        button.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        button.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.layer.cornerRadius = frame.height / 2
    }

    func calculatePadding() {
        if !(button.currentTitle ?? "").isEmpty {
            if button.currentTitle?.count ?? 0 < 4 {
                sidePadding = 38
            } else if button.currentTitle?.count ?? 0 < 7 {
                sidePadding = 26
            } else {
                sidePadding = 22
            }
            widthConstraint?.constant = sidePadding
        }
    }

    @objc func touchDown() {
        UIView.animate(withDuration: 0.1) {
            self.button.alpha = 0.5
            self.backgroundView.alpha = 0.5
        }
    }

    @objc func touchUp() {
        UIView.animate(withDuration: 0.2) {
            self.button.alpha = 1
            self.backgroundView.alpha = 1
        }
    }
}

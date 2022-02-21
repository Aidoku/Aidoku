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
                    self.activityIndicator.alpha = 1
                    self.buttonWidthConstraint?.isActive = false
                    self.buttonWidthConstraint = self.button.widthAnchor.constraint(equalToConstant: 28)
                    self.buttonWidthConstraint?.isActive = true
                }
            } else {
                UIView.animate(withDuration: 0.3) {
                    self.button.setTitle(self.buttonState == .fail ? "ERROR" : self.title, for: .normal)
                    self.activityIndicator.alpha = 0
                    self.buttonWidthConstraint?.isActive = false
                    self.buttonWidthConstraint = self.button.widthAnchor.constraint(equalTo: self.widthAnchor)
                    self.buttonWidthConstraint?.isActive = true
                }
            }
        }
    }

    var title: String? = "GET" {
        didSet {
            self.button.setTitle(title, for: .normal)
        }
    }

    let activityIndicator = UIActivityIndicatorView()
    let button = UIButton()
    var buttonWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)

        activityIndicator.startAnimating()
        activityIndicator.alpha = 0
        activityIndicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)

        button.backgroundColor = .tertiarySystemFill

        button.setTitle(self.title, for: .normal)
        button.setTitleColor(tintColor, for: .normal)

        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)

        button.addTarget(self, action: #selector(touchDown), for: .touchDown)
        button.addTarget(self, action: #selector(touchUp), for: .touchDragExit)
        button.addTarget(self, action: #selector(touchUp), for: .touchCancel)
        button.addTarget(self, action: #selector(touchUp), for: .touchUpInside)

        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)

        activityIndicator.centerYAnchor.constraint(equalTo: button.centerYAnchor).isActive = true
        activityIndicator.centerXAnchor.constraint(equalTo: button.centerXAnchor).isActive = true

        button.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        button.topAnchor.constraint(equalTo: topAnchor).isActive = true
        buttonWidthConstraint = button.widthAnchor.constraint(equalTo: widthAnchor)
        buttonWidthConstraint?.isActive = true
        button.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        button.layer.cornerRadius = frame.height / 2
    }

    @objc func touchDown() {
        UIView.animate(withDuration: 0.1) {
            self.button.alpha = 0.5
        }
    }

    @objc func touchUp() {
        UIView.animate(withDuration: 0.2) {
            self.button.alpha = 1
        }
    }
}

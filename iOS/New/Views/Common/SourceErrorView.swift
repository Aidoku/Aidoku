//
//  SourceErrorView.swift
//  Aidoku
//
//  Created by Skitty on 11/19/25.
//

import AidokuRunner
import UIKit

// uikit equivalent of ErrorView
class SourceErrorView: UIView {
    var onRetry: (() async -> Void)?

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        return stackView
    }()

    private lazy var imageView: UIImageView = {
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .title1))
        let imageView = UIImageView(image: .init(systemName: "exclamationmark.triangle.fill", withConfiguration: config))
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.font = UIFont.preferredFont(forTextStyle: .body)
        textLabel.textColor = .secondaryLabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        return textLabel
    }()

    private lazy var button: UIButton = {
        var buttonConfig = UIButton.Configuration.borderless()
        buttonConfig.title = NSLocalizedString("RETRY")
        buttonConfig.image = .init(systemName: "arrow.clockwise")
        buttonConfig.imagePadding = 6
        buttonConfig.imagePlacement = .leading
        buttonConfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let button = UIButton(configuration: buttonConfig)
        button.isHidden = true
        button.addTarget(self, action: #selector(retryPressed), for: .touchUpInside)
        return button
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView()
        view.isHidden = true
        return view
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
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(textLabel)
        stackView.addArrangedSubview(button)
        stackView.addArrangedSubview(loadingIndicator)

        addSubview(stackView)
    }

    func constrain() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingIndicator.widthAnchor.constraint(equalTo: widthAnchor) // fixes incorrect retry button width
        ])
    }

    func setError(_ error: Error?) {
        let text = if let error = error as? SourceError {
            switch error {
                case .missingResult:
                    NSLocalizedString("NO_RESULT")
                case .unimplemented:
                    NSLocalizedString("UNIMPLEMENTED")
                case .networkError:
                    NSLocalizedString("NETWORK_ERROR")
                case .message(let string):
                    NSLocalizedString(string)
            }
        } else if error is DecodingError {
            NSLocalizedString("DECODING_ERROR")
        } else {
            NSLocalizedString("UNKNOWN_ERROR")
        }

        textLabel.text = text

        if onRetry != nil {
            if let error = error as? SourceError {
                if case .unimplemented = error {
                    button.isHidden = true
                } else {
                    button.isHidden = false
                }
            } else {
                button.isHidden = true
            }
        }
    }

    func show(animated: Bool = true) {
        guard isHidden else { return }
        if animated {
            alpha = 0
            isHidden = false
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.alpha = 1
            }
        } else {
            isHidden = false
        }
    }

    func hide(animated: Bool = true) {
        guard !isHidden else { return }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                self.alpha = 0
            } completion: { _ in
                self.isHidden = true
                self.alpha = 1
            }
        } else {
            isHidden = true
        }
    }

    @objc private func retryPressed() {
        if let onRetry {
            button.isHidden = true
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimating()
            Task {
                await onRetry()
                loadingIndicator.isHidden = true
                button.isHidden = false
            }
        }
    }
}

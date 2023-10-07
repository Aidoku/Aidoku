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
        didSet {
            initText()
        }
    }

    private var expanded = false {
        didSet {
            if expanded {
                showFullText()
            } else {
                initText()
            }
        }
    }

    private let textLabel = UILabel()

    private let previewLength = 200
    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                          action: #selector(toggleExpanded))
        return tapGestureRecognizer
    }()

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
        textLabel.numberOfLines = 0
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        textLabel.topAnchor.constraint(equalTo: topAnchor).isActive = true
        textLabel.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        heightAnchor.constraint(equalTo: textLabel.heightAnchor).isActive = true
    }

    private func initText() {
        if let text = text, text.count > previewLength {

            let attributedString = NSMutableAttributedString(
                string: String(text.prefix(previewLength))
                    .trimmingCharacters(in: .whitespacesAndNewlines) + "... ")

            let more = NSMutableAttributedString(
                string: NSLocalizedString("MORE", comment: "Description expansion button"))

            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.systemRed
            ]

            more.addAttributes(attributes,
                               range: NSRange(location: 0, length: more.length))

            attributedString.append(more)

            textLabel.attributedText = attributedString
            textLabel.addGestureRecognizer(tapGestureRecognizer)
            textLabel.isUserInteractionEnabled = true

        } else {

            textLabel.text = text
            textLabel.removeGestureRecognizer(tapGestureRecognizer)
            textLabel.isUserInteractionEnabled = false
        }

        invalidateIntrinsicContentSize()
        sizeChangeListener?.sizeChanged(bounds.size)
    }

    private func showFullText() {
        UIView.transition(with: self,
                          duration: 0.3,
                          options: .transitionCrossDissolve) { [weak self] in

            guard let self = self else { return }
            self.textLabel.text = self.text
            self.invalidateIntrinsicContentSize()
            self.sizeChangeListener?.sizeChanged(self.bounds.size)
        }
    }

    @objc func toggleExpanded() {
        expanded.toggle()
    }
}

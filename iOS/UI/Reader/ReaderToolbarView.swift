//
//  ReaderToolbarView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class ReaderToolbarView: UIView {
    var currentPageValue: Int? {
        didSet {
            if oldValue != currentPageValue {
                let feedbackGenerator = UISelectionFeedbackGenerator()
                feedbackGenerator.selectionChanged()
            }
        }
    }
    var currentPage: Int? {
        didSet { updatePageLabels() }
    }
    var totalPages: Int? {
        didSet { updatePageLabels() }
    }

    let sliderView = ReaderSliderView()
    private let currentPageLabel = UILabel()
    private let pagesLeftLabel = UILabel()

    init() {
        super.init(frame: .zero)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        currentPageLabel.font = .systemFont(ofSize: 10)
        currentPageLabel.textAlignment = .center
        currentPageLabel.sizeToFit()
        currentPageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(currentPageLabel)

        pagesLeftLabel.font = .systemFont(ofSize: 10)
        pagesLeftLabel.textColor = .secondaryLabel
        pagesLeftLabel.textAlignment = .right
        pagesLeftLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pagesLeftLabel)

        sliderView.translatesAutoresizingMaskIntoConstraints = false
        sliderView.semanticContentAttribute = .playback // for rtl languages
        addSubview(sliderView)
    }

    func constrain() {
        NSLayoutConstraint.activate([
            currentPageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            currentPageLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            pagesLeftLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            pagesLeftLabel.bottomAnchor.constraint(equalTo: bottomAnchor),

            sliderView.heightAnchor.constraint(equalToConstant: 12),
            sliderView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            sliderView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            sliderView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    // allow slider thumb to be touched outside bounds
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews where subview is ReaderSliderView {
            if subview.subviews.contains(where: { $0.bounds.contains(convert(point, to: $0)) }) {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }

    func displayPage(_ page: Int) {
        guard let totalPages = totalPages else {
            return
        }
        var page = page
        if page > totalPages {
            page = totalPages
        } else if page < 1 {
            page = 1
        }
        currentPageLabel.text = String(format: NSLocalizedString("%i_OF_%i", comment: ""), page, totalPages)
        currentPageValue = page
    }

    func updatePageLabels() {
        guard var currentPage = currentPage, let totalPages = totalPages else {
            currentPageLabel.text = nil
            pagesLeftLabel.text = nil
            return
        }

        if currentPage > totalPages {
            currentPage = totalPages
        } else if currentPage < 1 {
            currentPage = 1
        }
        let pagesLeft = totalPages - currentPage
        currentPageLabel.text = String(format: NSLocalizedString("%i_OF_%i", comment: ""), currentPage, totalPages)
        if pagesLeft < 1 {
            pagesLeftLabel.text = nil
        } else {
            pagesLeftLabel.text = pagesLeft == 1
                ? NSLocalizedString("ONE_PAGE_LEFT", comment: "")
                : String(format: NSLocalizedString("%i_PAGES_LEFT", comment: ""), pagesLeft)
        }
    }

    func updateSliderPosition() {
        guard let currentPage = currentPage, let totalPages = totalPages else { return }
        sliderView.move(toValue: CGFloat(currentPage - 1) / max(CGFloat(totalPages - 1), 1))
    }
}

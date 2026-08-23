//
//  ReaderInfoPageView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/22/22.
//

import AidokuRunner
import UIKit

enum ReaderInfoPageType {
    case previous
    case next
}

class ReaderInfoPageView: UIView {
    var type: ReaderInfoPageType

    var currentChapter: AidokuRunner.Chapter? {
        didSet {
            updateLabelText()
        }
    }
    var previousChapter: AidokuRunner.Chapter? {
        didSet {
            updateLabelText()
        }
    }
    var nextChapter: AidokuRunner.Chapter? {
        didSet {
            updateLabelText()
        }
    }

    let noChapterLabel = UILabel()
    let skippingChaptersView = UIStackView()
    let skippingChaptersLabel = UILabel()

    let stackView = UIStackView()
    let topChapterLabel = UILabel()
    let topChapterTitleLabel = UILabel()
    let bottomChapterLabel = UILabel()
    let bottomChapterTitleLabel = UILabel()

    init(type: ReaderInfoPageType, currentChapter: AidokuRunner.Chapter? = nil) {
        self.type = type
        self.currentChapter = currentChapter

        super.init(frame: .zero)

        backgroundColor = .systemBackground

        stackView.distribution = .equalSpacing
        stackView.axis = .vertical
        stackView.spacing = 14
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let topStackView = UIStackView()
        topStackView.distribution = .equalSpacing
        topStackView.axis = .vertical
        topStackView.spacing = 2
        topChapterLabel.textColor = .label
        topChapterLabel.font = .systemFont(ofSize: 16, weight: .medium)
        topChapterTitleLabel.textColor = .secondaryLabel
        topChapterTitleLabel.font = .systemFont(ofSize: 16)
        topChapterTitleLabel.numberOfLines = 0

        skippingChaptersView.distribution = .equalSpacing
        skippingChaptersView.axis = .horizontal
        skippingChaptersView.spacing = 8
        skippingChaptersLabel.textColor = .secondaryLabel
        skippingChaptersLabel.textAlignment = .left
        skippingChaptersLabel.font = .systemFont(ofSize: 16)
        skippingChaptersLabel.numberOfLines = 0
        skippingChaptersLabel.translatesAutoresizingMaskIntoConstraints = false
        let warningIconView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
        warningIconView.tintColor = .systemYellow
        warningIconView.translatesAutoresizingMaskIntoConstraints = false
        warningIconView.contentMode = .center

        let bottomStackView = UIStackView()
        bottomStackView.distribution = .equalSpacing
        bottomStackView.axis = .vertical
        bottomStackView.spacing = 2
        bottomChapterLabel.textColor = .label
        bottomChapterLabel.font = .systemFont(ofSize: 16, weight: .medium)
        bottomChapterTitleLabel.textColor = .secondaryLabel
        bottomChapterTitleLabel.font = .systemFont(ofSize: 16)
        bottomChapterTitleLabel.numberOfLines = 0

        topStackView.addArrangedSubview(topChapterLabel)
        topStackView.addArrangedSubview(topChapterTitleLabel)
        skippingChaptersView.addArrangedSubview(warningIconView)
        skippingChaptersView.addArrangedSubview(skippingChaptersLabel)
        bottomStackView.addArrangedSubview(bottomChapterLabel)
        bottomStackView.addArrangedSubview(bottomChapterTitleLabel)

        stackView.addArrangedSubview(topStackView)
        stackView.addArrangedSubview(skippingChaptersView)
        stackView.addArrangedSubview(bottomStackView)

        addSubview(stackView)

        noChapterLabel.textColor = .secondaryLabel
        noChapterLabel.textAlignment = .center
        noChapterLabel.font = .systemFont(ofSize: 16)
        noChapterLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noChapterLabel)

        noChapterLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        noChapterLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        stackView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        stackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        stackView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 1, constant: -64).isActive = true

        updateLabelText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func chapterDifference(higherChapterNumber: Float, lowerChapterNumber: Float) -> Int {
        Int(floor(higherChapterNumber) - floor(lowerChapterNumber))
    }

    func updateLabelText() {
        guard let currentChapter else { return }
        if let previousChapter {
            topChapterLabel.text = NSLocalizedString("PREVIOUS_COLON")
            topChapterTitleLabel.text = previousChapter.formattedTitle()
            bottomChapterLabel.text = NSLocalizedString("CURRENT_COLON")
            bottomChapterTitleLabel.text = currentChapter.formattedTitle()
            if
                let currChapterNum = currentChapter.chapterNumber,
                let prevChapterNum = previousChapter.chapterNumber
            {
                let chapterDifference = chapterDifference(higherChapterNumber: currChapterNum, lowerChapterNumber: prevChapterNum)
                let shouldSkipChapters = chapterDifference > 1
                skippingChaptersView.isHidden = !shouldSkipChapters
                if shouldSkipChapters {
                    skippingChaptersLabel.text = String(format: NSLocalizedString("SKIPPING_CHAPTERS"), chapterDifference)
                }
            } else {
                skippingChaptersView.isHidden = true
            }
            noChapterLabel.isHidden = true
            stackView.isHidden = false
        } else if let nextChapter {
            topChapterLabel.text = NSLocalizedString("FINISHED_COLON")
            topChapterTitleLabel.text = currentChapter.formattedTitle()
            bottomChapterLabel.text = NSLocalizedString("NEXT_COLON")
            bottomChapterTitleLabel.text = nextChapter.formattedTitle()
            if
                let currChapterNum = currentChapter.chapterNumber,
                let nextChapterNum = nextChapter.chapterNumber
            {
                let chapterDifference = chapterDifference(higherChapterNumber: nextChapterNum, lowerChapterNumber: currChapterNum)
                let shouldSkipChapters = chapterDifference > 1
                skippingChaptersView.isHidden = !shouldSkipChapters
                if shouldSkipChapters {
                    skippingChaptersLabel.text = String(format: NSLocalizedString("SKIPPING_CHAPTERS"), chapterDifference)
                }
            } else {
                skippingChaptersView.isHidden = true
            }
            noChapterLabel.isHidden = true
            stackView.isHidden = false
        } else {
            noChapterLabel.text = type == .previous
                ? NSLocalizedString("NO_PREVIOUS_CHAPTER")
                : NSLocalizedString("NO_NEXT_CHAPTER")
            stackView.isHidden = true
            noChapterLabel.isHidden = false
            skippingChaptersView.isHidden = true
        }
    }
}

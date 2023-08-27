//
//  ChapterListHeaderConfiguration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import UIKit

enum ChapterSortOption: CaseIterable {
    case sourceOrder
    case chapter
    case uploadDate

    func toString() -> String {
        switch self {
        case .sourceOrder: return NSLocalizedString("SOURCE_ORDER", comment: "")
        case .chapter: return NSLocalizedString("CHAPTER", comment: "")
        case .uploadDate: return NSLocalizedString("UPLOAD_DATE", comment: "")
        }
    }
}

protocol ChapterSortDelegate: AnyObject {
    func sortOptionChanged(_ newOption: ChapterSortOption)
    func sortAscendingChanged(_ newValue: Bool)
}

struct ChapterListHeaderConfiguration: UIContentConfiguration {

    weak var delegate: ChapterSortDelegate?

    var chapterCount = 0
    var sortOption: ChapterSortOption = .sourceOrder
    var sortAscending = false

    func makeContentView() -> UIView & UIContentView {
        ChapterListHeaderContentView(self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        self
    }
}

class ChapterListHeaderContentView: UIView, UIContentView {

    var configuration: UIContentConfiguration {
        didSet {
            configure()
        }
    }

    private lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let sortImage: UIImage?
        if #available(iOS 15.0, *) {
            sortImage = UIImage(systemName: "line.3.horizontal.decrease")
        } else {
            sortImage = UIImage(systemName: "line.horizontal.3.decrease")
        }
        sortButton.showsMenuAsPrimaryAction = true
        sortButton.setImage(sortImage, for: .normal)
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }()

    private lazy var sortButton: UIButton = {
        let sortButton = UIButton(type: .roundedRect)
        return sortButton
    }()

    init(_ configuration: UIContentConfiguration) {
        self.configuration = configuration
        super.init(frame: .zero)

        addSubview(titleLabel)
        addSubview(sortButton)

        constrain()
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func constrain() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            titleLabel.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sortButton.leadingAnchor, constant: -12),

            sortButton.topAnchor.constraint(equalTo: topAnchor),
            sortButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            sortButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor, constant: -12)
        ])
    }

    func configure() {
        guard let configuration = configuration as? ChapterListHeaderConfiguration else { return }
        if configuration.chapterCount == 0 {
            titleLabel.text = NSLocalizedString("NO_CHAPTERS", comment: "")
        } else {
            titleLabel.text = "\(configuration.chapterCount) chapters"
        }
        sortButton.menu = makeSortMenu()
    }

    private func makeSortMenu() -> UIMenu? {
        guard let configuration = configuration as? ChapterListHeaderConfiguration else { return nil }
        return UIMenu(
            title: "",
            image: nil,
            identifier: nil,
            options: [],
            children: ChapterSortOption.allCases.map { option in
                UIAction(
                    title: option.toString(),
                    image: configuration.sortOption == option
                        ? UIImage(systemName: configuration.sortAscending ? "chevron.up" : "chevron.down")
                        : nil
                ) { [weak self] _ in
                    guard
                        let self = self,
                        var configuration = self.configuration as? ChapterListHeaderConfiguration
                    else { return }

                    if configuration.sortOption == option {
                        configuration.sortAscending.toggle()
                    } else {
                        configuration.sortAscending = false
                        configuration.sortOption = option
                        configuration.delegate?.sortOptionChanged(configuration.sortOption)
                    }
                    configuration.delegate?.sortAscendingChanged(configuration.sortAscending)

                    self.configuration = configuration
                    self.sortButton.menu = self.makeSortMenu() // refresh sort menu
                }
            }
        )
    }
}

//
//  LibraryCategorySelectionHeader.swift
//  Aidoku
//
//  Created by Skitty on 2/25/26.
//

import UIKit

// based on MangaListSelectionHeaderDelegate

protocol LibraryCategorySelectionHeaderDelegate: AnyObject {
    func optionSelected(_ indexPath: IndexPath)
}

class LibraryCategorySelectionHeader: UICollectionReusableView {
    weak var delegate: LibraryCategorySelectionHeaderDelegate?

    struct Section {
        var title: String?
        var options: [String] = []
    }
    var options: [Section] = [] {
        didSet { updateMenu() }
    }
    var lockedOptions: [IndexPath] = [] {
        didSet { updateMenu() }
    }

    private let titleLabel = UILabel()
    private let menuButton = UIButton(type: .roundedRect)

    private var selectedSection: Int = 0
    private var selectedOption: Int = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure() {
        titleLabel.textColor = .secondaryLabel
        addSubview(titleLabel)

        menuButton.tintColor = .label
        menuButton.setImage(
            UIImage(
                systemName: "chevron.down",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)
            ),
            for: .normal
        )

        // Move chevron to right side
        menuButton.configuration = .plain()
        menuButton.configuration?.imagePadding = 3
        menuButton.configuration?.imagePlacement = .trailing
        menuButton.configuration?.contentInsets = .zero

        updateMenu()
        menuButton.showsMenuAsPrimaryAction = true
        addSubview(menuButton)
    }

    func constrain() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),

            menuButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 5),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4)
        ])
    }

    func updateMenu() {
        var menus: [UIMenuElement] = []
        for (i, section) in options.enumerated() {
            var children: [UIAction] = []
            for (j, option) in section.options.enumerated() {
                let indexPath = IndexPath(row: j, section: i)
                let selected = selectedSection == i && selectedOption == j
                children.append(
                    UIAction(
                        title: option,
                        image: lockedOptions.contains(indexPath) ? UIImage(systemName: "lock.fill") : nil,
                        state: selected ? .on : .off
                    ) { _ in
                        self.setSelectedOption(indexPath)
                    }
                )
            }
            menus.append(UIMenu(title: section.title ?? "", options: .displayInline, children: children))
        }
        let menu = UIMenu(children: menus)
        menuButton.menu = menu

        let title = options[safe: selectedSection]?.options[safe: selectedOption] ?? ""
        menuButton.setTitle(title, for: .normal)
    }

    func setSelectedOption(_ indexPath: IndexPath) {
        selectedSection = indexPath.section
        selectedOption = indexPath.row
        updateMenu()
        delegate?.optionSelected(indexPath)
    }
}

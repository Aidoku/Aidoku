//
//  MangaListSelectionHeader.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit

protocol MangaListSelectionHeaderDelegate: AnyObject {
    func optionSelected(_ index: Int)
}

class MangaListSelectionHeader: UICollectionReusableView {

    weak var delegate: MangaListSelectionHeaderDelegate?

    let titleLabel = UILabel()
    let menuButton = UIButton(type: .roundedRect)

    let filterButton = UIButton(type: .roundedRect)

    var title: String? {
        didSet {
            titleLabel.text = title
        }
    }
    var options: [String] = [] {
        didSet {
            updateMenu()
        }
    }
    var selectedOption: Int = 0
    var lockedOptions: [Int] = [] {
        didSet {
            updateMenu()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutViews() {
        titleLabel.text = title
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        menuButton.tintColor = .label
        menuButton.setImage(UIImage(systemName: "chevron.down",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)

        // Move chevron to right side
        if #available(iOS 15.0, *) {
            menuButton.configuration = .plain()
            menuButton.configuration?.imagePadding = 3
            menuButton.configuration?.imagePlacement = .trailing
            menuButton.configuration?.contentInsets = .zero
        } else {
            menuButton.transform = CGAffineTransform(scaleX: -1, y: 1)
            menuButton.titleLabel?.transform = CGAffineTransform(scaleX: -1, y: 1)
            menuButton.imageView?.transform = CGAffineTransform(scaleX: -1, y: 1)
        }

        updateMenu()
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)

        filterButton.alpha = 0
        if #available(iOS 15.0, *) {
            filterButton.setImage(UIImage(systemName: "line.3.horizontal.decrease"), for: .normal)
        } else {
            filterButton.setImage(UIImage(systemName: "line.horizontal.3.decrease"), for: .normal)
        }
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(filterButton)

        titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16).isActive = true
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4).isActive = true

        menuButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 5).isActive = true
        menuButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4).isActive = true

        filterButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16).isActive = true
        filterButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4).isActive = true
    }

    func updateMenu() {
        var children: [UIAction] = []
        for (i, option) in options.enumerated() {
            children.append(
                UIAction(
                    title: option,
                    image: lockedOptions.contains(i) ? UIImage(systemName: "lock.fill") : nil,
                    state: selectedOption == i ? .on : .off
                ) { _ in
                    self.setSelectedOption(i)
                }
            )
        }
        let menu = UIMenu(title: "", image: nil, identifier: nil, options: [], children: children)
        menuButton.menu = menu
        if options.count > selectedOption {
            menuButton.setTitle(options[selectedOption], for: .normal)
        } else {
            menuButton.setTitle("", for: .normal)
        }
    }

    func setSelectedOption(_ option: Int) {
        selectedOption = option
        updateMenu()
        delegate?.optionSelected(selectedOption)
    }
}

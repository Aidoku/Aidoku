//
//  ChapterListHeaderConfiguration.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/1/23.
//

import UIKit

protocol ChapterSortDelegate: AnyObject {
    func sortOptionChanged(_ newOption: ChapterSortOption)
    func sortAscendingChanged(_ newValue: Bool)
    func filtersChanged(_ newFilters: [ChapterFilterOption])
    func langFilterChanged(_ newValue: String?)
}

struct ChapterListHeaderConfiguration: UIContentConfiguration {

    weak var delegate: ChapterSortDelegate?

    var chapterCount = 0
    var sortOption: ChapterSortOption = .sourceOrder
    var sortAscending = false
    var filters: [ChapterFilterOption] = []
    var langFilter: String?
    var sourceLangs: [String] = []

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
        sortButton.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu? {
        guard let configuration = configuration as? ChapterListHeaderConfiguration else { return nil }

        var filterChildren: [UIMenuElement] = filterOptions(configuration: configuration)
        if configuration.sourceLangs.count > 1 {
            filterChildren.append(languageFilterMenu(configuration: configuration))
        }

        return UIMenu(
            title: "",
            children: [
                UIMenu(
                    title: NSLocalizedString("SORT_BY", comment: ""),
                    options: .displayInline,
                    children: sortActions(configuration: configuration)
                ),
                UIMenu(
                    title: NSLocalizedString("FILTER_BY", comment: ""),
                    options: .displayInline,
                    children: filterChildren
                )
            ]
        )
    }

    private func sortActions(configuration: ChapterListHeaderConfiguration) -> [UIAction] {
        ChapterSortOption.allCases.map { option in
            UIAction(
                title: option.stringValue,
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

                menuOptionChanged(configuration: configuration)
            }
        }
    }

    private func filterOptions(configuration: ChapterListHeaderConfiguration) -> [UIAction] {
        ChapterFilterMethod.allCases.map { option in
            let filterIdx = configuration.filters.firstIndex(where: { $0.type == option })
            return UIAction(
                title: option.stringValue,
                image: filterIdx != nil
                    ? UIImage(systemName: configuration.filters[filterIdx!].exclude ? "xmark" : "checkmark")
                    : nil
            ) { [weak self] _ in
                guard
                    let self = self,
                    var configuration = self.configuration as? ChapterListHeaderConfiguration
                else { return }

                if let filterIdx {
                    if configuration.filters[filterIdx].exclude {
                        configuration.filters.remove(at: filterIdx)
                    } else {
                        configuration.filters[filterIdx].exclude = true
                    }
                } else {
                    configuration.filters.append(ChapterFilterOption(type: option, exclude: false))
                }
                configuration.delegate?.filtersChanged(configuration.filters)

                menuOptionChanged(configuration: configuration)
            }
        }
    }

    private func languageFilterMenu(configuration: ChapterListHeaderConfiguration) -> UIMenu {
        UIMenu(
            title: NSLocalizedString("LANGUAGE", comment: ""),
            children: configuration.sourceLangs.map { lang in
                UIAction(
                    title: (Locale.current as NSLocale).displayName(forKey: .identifier, value: lang) ?? "",
                    image: configuration.langFilter == lang
                        ? UIImage(systemName: "checkmark")
                        : nil
                ) { [weak self] _ in
                    guard
                        let self = self,
                        var configuration = self.configuration as? ChapterListHeaderConfiguration
                    else { return }

                    let langValue = configuration.langFilter == lang ? nil : lang
                    configuration.langFilter = langValue
                    configuration.delegate?.langFilterChanged(langValue)

                    menuOptionChanged(configuration: configuration)
                }
            }
        )
    }

    private func menuOptionChanged(configuration: ChapterListHeaderConfiguration) {
        self.configuration = configuration
        sortButton.menu = makeMenu() // refresh sort menu
    }
}

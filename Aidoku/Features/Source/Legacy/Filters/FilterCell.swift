//
//  FilterCollapsibleCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/14/22.
//

import UIKit

class FilterCell: UIView {

    let filter: FilterBase
    let parent: FilterCell?
    var selectedFilters: SelectedFilters

    let titleLabel = UILabel()
    let symbolView = UIImageView()

    var detailView: FilterStackView?

    var selectedIntValue: Int? {
        get {
            (selectedFilters.filters.first(where: { $0.name == parent?.filter.name ?? "" }) as? SelectFilter)?.value
        }
        set {
            if let newValue = newValue,
               let parent = parent,
               let parentFilter = parent.filter as? SelectFilter {
                var newArray = selectedFilters.filters.filter { $0.name != parent.filter.name }
                parentFilter.value = newValue
                newArray.append(parentFilter)
                selectedFilters.filters = newArray
                parent.detailView?.updateCellImages()
            }
        }
    }

    var selectedSortValue: SortSelection {
        get {
            (selectedFilters.filters.first {
                $0.name == parent?.filter.name ?? ""
            } as? SortFilter)?.value ?? SortSelection(index: 0, ascending: false)
        }
        set {
            if let parent = parent,
               let parentFilter = parent.filter as? SortFilter {
                var newArray = selectedFilters.filters.filter { $0.name != parent.filter.name }
                parentFilter.value = newValue
                newArray.append(parentFilter)
                selectedFilters.filters = newArray
                parent.detailView?.updateCellImages()
            }
        }
    }

    init(filter: FilterBase, parent: FilterCell? = nil, selectedFilters: SelectedFilters) {
        self.filter = filter
        self.parent = parent
        self.selectedFilters = selectedFilters
        super.init(frame: .zero)
        layoutViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutViews() {
        var insets: CGFloat = 22

        titleLabel.text = filter.name
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        if filter is GroupFilter || filter is SortFilter || filter is SelectFilter {
            insets = 16
            if let filter = filter as? GroupFilter {
                detailView = FilterStackView(filters: filter.filters, parent: self, selectedFilters: selectedFilters)
            } else if let filter = filter as? SortFilter {
                detailView = FilterStackView(filters: filter.options.map { StringFilter(value: $0) }, parent: self, selectedFilters: selectedFilters)
            } else if let filter = filter as? SelectFilter {
                detailView = FilterStackView(filters: filter.options.map { StringFilter(value: $0) }, parent: self, selectedFilters: selectedFilters)
            }
            detailView?.alpha = 0
            detailView?.isHidden = true
        }
        updateImage()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)

        titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: insets).isActive = true
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

        symbolView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -insets).isActive = true
        symbolView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        backgroundColor = .secondarySystemFill
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)

        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = .clear

            if let detailView = self.detailView {
                let hiding = !detailView.isHidden
                detailView.isHidden = hiding
                detailView.alpha = hiding ? 0 : 1

                self.symbolView.transform = hiding ? CGAffineTransform.identity : CGAffineTransform(scaleX: 1, y: -1)
            }
        }

        if let filter = filter as? StringFilter {
            if let parent = parent?.filter as? SortFilter,
               let index = parent.options.firstIndex(of: filter.value) {
                selectedSortValue = SortSelection(
                    index: index,
                    ascending: parent.canAscend ? parent.value.index == index && !selectedSortValue.ascending : false
                )
            } else if let parent = parent?.filter as? SelectFilter,
                      let index = parent.options.firstIndex(of: filter.value) {
                if selectedIntValue != index {
                    selectedIntValue = index
                }
            }
        } else if filter is CheckFilter {
            toggleSelectedValue()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = .clear
        }
    }

    func updateImage() {
        if filter is GroupFilter || filter is SortFilter || filter is SelectFilter {
            symbolView.image = UIImage(systemName: "chevron.down",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            symbolView.tintColor = .label
            if !(detailView?.isHidden ?? true) {
                symbolView.transform = CGAffineTransform(scaleX: 1, y: -1)
            }
        } else if let filter = filter as? StringFilter {
            if let parent = parent?.filter as? SortFilter,
               let index = parent.options.firstIndex(of: filter.value) {
                if index == selectedSortValue.index {
                    symbolView.image = UIImage(systemName: selectedSortValue.ascending ? "chevron.up" : "chevron.down")
                } else {
                    symbolView.image = nil
                }
            } else if let parent = parent?.filter as? SelectFilter,
                      let index = parent.options.firstIndex(of: filter.value) {
                if index == selectedIntValue {
                    symbolView.image = UIImage(systemName: "checkmark")
                } else {
                    symbolView.image = nil
                }
            }
        } else if let filter = filter as? CheckFilter {
            if let value = filter.value {
                symbolView.image = UIImage(systemName: value ? "checkmark" : "xmark")
            } else {
                symbolView.image = nil
            }
        }
    }

    func toggleSelectedValue() {
        var newArray = selectedFilters.filters
        if let filter = filter as? CheckFilter {
            newArray = newArray.filter { $0.id != filter.id }
            if filter.value == true && filter.canExclude {
                filter.value = false
            } else if filter.value == false || (filter.value == true && !filter.canExclude) {
                filter.value = nil
            } else {
                filter.value = true
            }
            newArray.append(filter)
        }
        selectedFilters.filters = newArray

        parent?.detailView?.updateCellImages()
        updateImage()
    }
}

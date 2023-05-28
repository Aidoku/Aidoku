//
//  FilterStackView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/14/22.
//

import UIKit

class FilterStackView: UIStackView {

    let filters: [FilterBase]
    let parent: FilterCell?
    var selectedFilters: SelectedFilters

    var cells: [FilterCell] = []

    let cellHeight: CGFloat = 40

    init(filters: [FilterBase], parent: FilterCell? = nil, selectedFilters: SelectedFilters) {
        self.filters = filters
        self.parent = parent
        self.selectedFilters = selectedFilters
        super.init(frame: .zero)
        layoutViews()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutViews() {
        axis = .vertical
        distribution = .equalSpacing
        spacing = 4

        cells = []
        for filter in filters {
            let cell = FilterCell(filter: filter, parent: parent, selectedFilters: selectedFilters)
            cell.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(cell)

            if let detailView = cell.detailView {
                detailView.translatesAutoresizingMaskIntoConstraints = false
                addArrangedSubview(detailView)

                detailView.widthAnchor.constraint(equalTo: cell.widthAnchor).isActive = true
            }

            cell.heightAnchor.constraint(equalToConstant: cellHeight).isActive = true
            cell.widthAnchor.constraint(equalTo: widthAnchor).isActive = true

            cells.append(cell)
        }
    }

    func updateCellImages() {
        for cell in cells {
            cell.updateImage()
        }
    }
}

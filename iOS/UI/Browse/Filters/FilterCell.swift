//
//  FilterCollapsibleCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/14/22.
//

import UIKit

class FilterCell: UIView {
    
    let filter: Filter
    let parent: FilterCell?
    var selectedFilters: SelectedFilters
    
    let titleLabel = UILabel()
    let symbolView = UIImageView()
    
    var detailView: FilterStackView?
    
    var selectedIntValue: Int? {
        selectedFilters.filters.filter({ $0.name == filter.name }).first?.value as? Int
    }
    
    var boolValue: Bool {
        filter.value as? Bool ?? false
    }
    
    var selectedSortValue: SortOption {
        get {
            selectedFilters.filters.first { $0.name == parent?.filter.name ?? "" }?.value as? SortOption ?? SortOption(index: 0, name: "", ascending: false)
        }
        set {
            if let parent = parent {
                var newArray = selectedFilters.filters.filter { $0.name != parent.filter.name }
                newArray.append(Filter(type: .sort, name: parent.filter.name, value: newValue))
                selectedFilters.filters = newArray
                parent.detailView?.updateCellImages()
            }
        }
    }
    
    init(filter: Filter, parent: FilterCell? = nil, selectedFilters: SelectedFilters) {
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
        
        if filter.type == .group || filter.type == .sort {
            insets = 16
            detailView = FilterStackView(filters: filter.value as? [Filter] ?? [], parent: self, selectedFilters: selectedFilters)
            detailView?.alpha = 0
            detailView?.isHidden = true
        }
        updateImage()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolView)
        
        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets).isActive = true
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        
        symbolView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets).isActive = true
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
        if filter.type == .sortOption {
            if let option = filter.value as? SortOption {
                let asc = filter.name == selectedSortValue.name && !selectedSortValue.ascending
                selectedSortValue = SortOption(index: option.index, name: option.name, ascending: asc)
            }
        } else if filter.type == .check || filter.type == .genre {
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
        if filter.type == .group || filter.type == .sort {
            symbolView.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
            symbolView.tintColor = .label
            if !(detailView?.isHidden ?? true) {
                symbolView.transform = CGAffineTransform(scaleX: 1, y: -1)
            }
        } else if filter.type == .sortOption {
            if filter.name == selectedSortValue.name {
                symbolView.image = UIImage(systemName: selectedSortValue.ascending ? "chevron.up" : "chevron.down")
            } else {
                symbolView.image = nil
            }
        } else if filter.type == .check || filter.type == .genre {
            if let value = selectedIntValue {
                symbolView.image = UIImage(systemName: value == 1 ? "checkmark" : "xmark")
            } else {
                symbolView.image = nil
            }
        }
    }
    
    func toggleSelectedValue() {
        var newArray = selectedFilters.filters
        if let value = selectedIntValue {
            newArray = newArray.filter { $0.name != filter.name }
            if value == 1 && boolValue { // exclude
                newArray.append(Filter(type: filter.type, name: filter.name, value: 2))
            }
        } else {
            newArray.append(Filter(type: filter.type, name: filter.name, value: 1))
        }
        selectedFilters.filters = newArray
        
        parent?.detailView?.updateCellImages()
    }
}

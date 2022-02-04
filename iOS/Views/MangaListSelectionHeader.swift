//
//  MangaListSelectionHeader.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/29/22.
//

import UIKit

protocol MangaListSelectionHeaderDelegate {
    func optionSelected(_ index: Int)
}

class MangaListSelectionHeader: UICollectionReusableView {
    
    var delegate: MangaListSelectionHeaderDelegate?
    
    let titleLabel = UILabel()
    let menuButton = UIButton(type: .roundedRect)
    
    var title: String? = nil {
        didSet {
            titleLabel.text = title
        }
    }
    var options: [String] = [] {
        didSet {
            updateMenu()
        }
    }
    var selectedOption: Int = 0 {
        didSet {
            updateMenu()
            delegate?.optionSelected(selectedOption)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateMenu() {
        var children: [UIAction] = []
        for (i, option) in options.enumerated() {
            children.append(
                UIAction(title: option, image: selectedOption == i ? UIImage(systemName: "checkmark") : nil) { _ in
                    self.selectedOption = i
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
    
    func layoutViews() {
        titleLabel.text = title
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        menuButton.tintColor = .label
        menuButton.setImage(UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13)), for: .normal)
        
        // Move chevron to right side
        if #available(iOS 15.0, *) {
            menuButton.configuration = .plain()
            menuButton.configuration?.imagePadding = 3
            menuButton.configuration?.imagePlacement = .trailing
            menuButton.configuration?.contentInsets = .zero
        } else {
            menuButton.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
            menuButton.titleLabel?.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
            menuButton.imageView?.transform = CGAffineTransform(scaleX: -1.0, y: 1.0)
        }
        
        updateMenu()
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(menuButton)
        
        titleLabel.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16).isActive = true
        titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4).isActive = true
        
        menuButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 5).isActive = true
        menuButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4).isActive = true
    }
}

//
//  SourceSectionHeaderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/8/22.
//

import UIKit

class SourceSectionHeaderView: UITableViewHeaderFooterView {

    let title = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        configureContents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureContents() {
        textLabel?.isHidden = true

        // TODO: use contentConfiguration instead
        title.font = .systemFont(ofSize: 16, weight: .medium)
        title.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(title)

        NSLayoutConstraint.activate([
            title.heightAnchor.constraint(equalToConstant: 20),
            title.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

// class SmallSectionHeaderContentView: UIView, UIContentView {
//    var configuration: UIContentConfiguration
//
//    init(_ configuration: UIContentConfiguration) {
//        self.configuration = configuration
//        super.init(frame:.zero)
//    }
// }

//
//  UINavigationItem.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

extension UINavigationItem {

    func setTitle(upper: String?, lower: String) {
        if let upper = upper {
            let upperLabel = UILabel()
            upperLabel.text = upper
            upperLabel.font = UIFont.systemFont(ofSize: 11)
            upperLabel.textColor = .secondaryLabel

            let lowerLabel = UILabel()
            lowerLabel.text = lower
            lowerLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            lowerLabel.textAlignment = .center

            let stackView = UIStackView(arrangedSubviews: [upperLabel, lowerLabel])
            stackView.distribution = .equalCentering
            stackView.axis = .vertical
            stackView.alignment = .center

            let width = max(upperLabel.frame.size.width, lowerLabel.frame.size.width)
            stackView.frame = CGRect(x: 0, y: 0, width: width, height: 35)

            upperLabel.sizeToFit()
            lowerLabel.sizeToFit()

            self.titleView = stackView
        } else {
            self.titleView = nil
            self.title = lower
        }
    }
}

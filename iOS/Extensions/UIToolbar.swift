//
//  UIToolbar.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

extension UIToolbar {

    var contentView: UIView? {
        subviews.first { view in
            let viewDescription = String(describing: type(of: view))
            return viewDescription.contains("ContentView")
        }
    }

    var stackView: UIView? {
        contentView?.subviews.first { view -> Bool in
            let viewDescription = String(describing: type(of: view))
            return viewDescription.contains("ButtonBarStackView")
        }
    }

   func fitContentViewToToolbar() {
        guard let stackView = stackView, let contentView = contentView else { return }
        stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
        stackView.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true
    }
}

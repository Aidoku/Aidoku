//
//  HostingNode.swift
//  Aidoku
//
//  Created by Skitty on 5/20/25.
//

import AsyncDisplayKit
import SwiftUI

class HostingNode<Content: View>: ASDisplayNode {
    var content: Content

    init(content: Content) {
        self.content = content
        super.init()

        setViewBlock { [weak self] in
            guard let self else { return UIView() }
            let view = _UIHostingView(rootView: self.content)
            view.backgroundColor = .systemBackground // text page should have a background color
            view.isUserInteractionEnabled = true
            return view
        }
        isUserInteractionEnabled = true
    }
}

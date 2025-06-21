//
//  HostingNode.swift
//  Aidoku
//
//  Created by Skitty on 5/20/25.
//

import AsyncDisplayKit
import SwiftUI

class HostingNode<Content: View>: ASDisplayNode {
    weak var parentViewController: UIViewController?
    var content: Content

    private var viewController: UIViewController?

    init(
        parentViewController: UIViewController? = nil,
        content: Content
    ) {
        self.parentViewController = parentViewController
        self.content = content
        super.init()

        setViewBlock { [weak self] in
            guard let self else { return UIView() }
            let hostingController = self.makeHostingController()
            self.viewController = hostingController
            parentViewController?.addChild(hostingController)
            return hostingController.view
        }
        isUserInteractionEnabled = true
    }

    private func makeHostingController() -> UIViewController {
        let controller = UIHostingController(rootView: content)
        if #available(iOS 16.4, *) {
            controller.safeAreaRegions = []
        }
        controller.view.backgroundColor = .systemBackground // text page should have a background color
        controller.view.isUserInteractionEnabled = true
        return controller
    }
}

//
//  HostingController.swift
//  Aidoku
//
//  Created by Skitty on 7/20/22.
//

import SwiftUI

final class HostingController<Content: View>: UIHostingController<Content> {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.view.invalidateIntrinsicContentSize()
    }
}

private protocol AnyUIHostingViewController: AnyObject {}
extension UIHostingController: AnyUIHostingViewController {}

extension UIViewController {
    /// Checks if this UIViewController is wrapped inside of SwiftUI. Must be used after viewDidLoad
    var isWrapped: Bool { parent is AnyUIHostingViewController }
}

//
//  HostingController.swift
//  Aidoku
//
//  Created by Skitty on 7/20/22.
//

import SwiftUI

final class HostingController<Content: View>: UIHostingController<Content> {
    /// When true, skips `invalidateIntrinsicContentSize` during layout.
    /// Used by the scroll text reader to prevent size recalculation during bar transitions.
    var suppressInvalidation = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !suppressInvalidation {
            self.view.invalidateIntrinsicContentSize()
        }
    }
}

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

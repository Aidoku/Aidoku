//
//  HostingController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import UIKit
import SwiftUI

class HostingController<Content>: UIHostingController<Content> where Content: View {
    
    override var childForStatusBarHidden: UIViewController? {
        children.first
    }

    override var childForStatusBarStyle: UIViewController? {
        children.first
    }
    
    override init(rootView: Content) {
        super.init(rootView: rootView)
        
        self.modalPresentationCapturesStatusBarAppearance = true

        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusBar), name: Notification.Name("updateStatusBar"), object: nil)
    }
    
    @objc func updateStatusBar() {
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}

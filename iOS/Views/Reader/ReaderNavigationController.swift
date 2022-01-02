//
//  ReaderNavigationController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import UIKit

class ReaderNavigationController: UINavigationController {
    
    override var childForStatusBarHidden: UIViewController? {
        viewControllers.first
    }

    override var childForStatusBarStyle: UIViewController? {
        viewControllers.first
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.modalPresentationCapturesStatusBarAppearance = true
    }
}

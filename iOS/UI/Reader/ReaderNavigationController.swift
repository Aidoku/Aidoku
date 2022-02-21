//
//  ReaderNavigationController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/23/21.
//

import UIKit

class ReaderNavigationController: UINavigationController {

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }

    override var childForStatusBarStyle: UIViewController? {
        topViewController
    }
}

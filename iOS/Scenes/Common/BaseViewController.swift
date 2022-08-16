//
//  BaseViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/15/22.
//

import UIKit

class BaseViewController: UIViewController {

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configure()
        constrain()
    }

    func configure() {}
    func constrain() {}
}

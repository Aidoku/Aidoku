//
//  BaseObservingViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import UIKit

class BaseObservingViewController: BaseViewController {

    private var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func addObserver(forName name: String, object: Any? = nil, using block: @escaping (Notification) -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name(name), object: object, queue: nil, using: block
        ))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observe()
    }

    func observe() {}
}

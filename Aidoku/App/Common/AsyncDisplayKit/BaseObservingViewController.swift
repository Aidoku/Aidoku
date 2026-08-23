//
//  BaseObservingViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 8/2/22.
//

import UIKit
import Combine

class BaseObservingViewController: BaseViewController {
    var cancellables = Set<AnyCancellable>()

    func addObserver(forName name: NSNotification.Name, object: Any? = nil, using block: @escaping (Notification) -> Void) {
        NotificationCenter.default.publisher(for: name)
            .sink(receiveValue: block)
            .store(in: &cancellables)
    }

    func addObserver(forName name: String, object: Any? = nil, using block: @escaping (Notification) -> Void) {
        addObserver(forName: NSNotification.Name(name), object: object, using: block)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observe()
    }

    func observe() {}
}

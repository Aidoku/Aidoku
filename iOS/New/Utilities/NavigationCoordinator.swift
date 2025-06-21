//
//  NavigationCoordinator.swift
//  Aidoku
//
//  Created by Skitty on 4/28/25.
//

import SwiftUI

@MainActor
class NavigationCoordinator: ObservableObject {
    weak var rootViewController: UIViewController?

    init(rootViewController: UIViewController?) {
        self.rootViewController = rootViewController
    }

    func push<V: View>(_ view: V, animated: Bool = true, title: String? = nil) {
        let vc = UIHostingController(rootView: view.environmentObject(self))
        vc.title = title
        rootViewController?.navigationController?.pushViewController(vc, animated: animated)
    }

    func push(_ viewController: UIViewController, animated: Bool = true) {
        rootViewController?.navigationController?.pushViewController(viewController, animated: animated)
    }

//    func present<V: View>(_ view: V, animated: Bool = true) {
//        let vc = UIHostingController(rootView: view.environmentObject(self))
//        rootViewController?.present(vc, animated: animated)
//    }

    func present(_ viewController: UIViewController, animated: Bool = true) {
        rootViewController?.present(viewController, animated: animated)
    }

//    func pop(animated: Bool = true) {
//        rootViewController?.navigationController?.popViewController(animated: animated)
//    }

    func dismiss(animated: Bool = true) {
        rootViewController?.dismiss(animated: animated)
    }
}

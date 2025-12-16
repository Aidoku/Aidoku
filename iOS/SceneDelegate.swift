//
//  SceneDelegate.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/29/21.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let bannerHeight: CGFloat = 30

    var window: UIWindow?
    private var incognitoBannerView: UIView?

    var totalBannerHeight: CGFloat {
        incognitoBannerView?.frame.height ?? 0
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = TabBarController()
            window.tintColor = .systemPink

            if UserDefaults.standard.bool(forKey: "General.useSystemAppearance") {
                window.overrideUserInterfaceStyle = .unspecified
            } else {
                if UserDefaults.standard.integer(forKey: "General.appearance") == 0 {
                    window.overrideUserInterfaceStyle = .light
                } else {
                    window.overrideUserInterfaceStyle = .dark
                }
            }

            self.window = window
            window.makeKeyAndVisible()

            let incognitoBannerView = IncognitoBannerView()
            self.incognitoBannerView = incognitoBannerView
            incognitoBannerView.translatesAutoresizingMaskIntoConstraints = false
            window.insertSubview(incognitoBannerView, at: 0)

            NSLayoutConstraint.activate([
                incognitoBannerView.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                incognitoBannerView.trailingAnchor.constraint(equalTo: window.trailingAnchor),
                incognitoBannerView.topAnchor.constraint(equalTo: window.topAnchor),
                incognitoBannerView.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: Self.bannerHeight)
            ])
        }

        if
            let url = connectionOptions.urlContexts.first?.url,
            let delegate = UIApplication.shared.delegate as? AppDelegate
        {
            delegate.handleUrl(url: url)
        }
    }

    let contentHideView: UIView = {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .systemBackground
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()

    func sceneWillEnterForeground(_ scene: UIScene) {
        contentHideView.removeFromSuperview()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        contentHideView.removeFromSuperview()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        let incognitoEnabled = UserDefaults.standard.bool(forKey: "General.incognitoMode")
        if incognitoEnabled {
            (scene as? UIWindowScene)?.windows.first?.addSubview(contentHideView)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url, let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.handleUrl(url: url)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: any UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        let newOrientation = if #available(iOS 16.0, *) {
            windowScene.effectiveGeometry.interfaceOrientation
        } else {
            windowScene.interfaceOrientation
        }
        guard newOrientation != previousInterfaceOrientation else { return }
        NotificationCenter.default.post(name: .orientationDidChange, object: newOrientation)
    }
}

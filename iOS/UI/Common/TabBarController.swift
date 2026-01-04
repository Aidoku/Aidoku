//
//  TabBarController.swift
//  Aidoku
//
//  Created by Skitty on 7/26/25.
//

import Combine
import SwiftUI
import SwiftUIIntrospect

class TabBarController: UITabBarController {
    private var originalFrame: CGRect = .zero
    private var shrunkFrame: CGRect = .zero
    private var cancellables: [AnyCancellable] = []

    private var settingsPath: NavigationCoordinator?
    private var previousSelectedIndex: Int?

    private lazy var libraryProgressView = CircularProgressView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))

    private lazy var libraryRefreshAccessory: UIView = {
        let view = UIView()

        let label = UILabel()
        label.text = NSLocalizedString("REFRESHING_LIBRARY")
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        libraryProgressView.radius = 12
        libraryProgressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(libraryProgressView)

        if #unavailable(iOS 26) {
            // add styling for older versions without the bottom accessory view
            let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            backgroundView.layer.cornerRadius = 48 / 2
            backgroundView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
            backgroundView.layer.borderWidth = 1
            backgroundView.clipsToBounds = true
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(backgroundView, at: 0)

            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: libraryProgressView.leadingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.heightAnchor.constraint(equalToConstant: 48),

            libraryProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            libraryProgressView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            libraryProgressView.widthAnchor.constraint(equalToConstant: 20),
            libraryProgressView.heightAnchor.constraint(equalToConstant: 20)
        ])

        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        delegate = self

        let libraryViewController = NavigationController(rootViewController: LibraryViewController())
        let browseViewController = NavigationController(rootViewController: BrowseViewController())
        let searchViewController = NavigationController(rootViewController: SearchViewController())

        let historyPath = NavigationCoordinator(rootViewController: nil)
        let historyHostingController = UIHostingController(rootView: HistoryView()
            .environmentObject(historyPath))
        historyPath.rootViewController = historyHostingController
        let historyViewController = NavigationController(rootViewController: historyHostingController)

        let settingsPath = NavigationCoordinator(rootViewController: nil)
        let settingsViewController: UIViewController
        if UIDevice.current.userInterfaceIdiom == .pad {
            // this breaks the zoom transitions from the toolbar buttons in the backups setting page
            let hosting = UIHostingController(rootView: SettingsView().environmentObject(settingsPath))
            let entity = NavigationController(rootViewController: hosting)
            settingsPath.rootViewController = entity
            settingsViewController = entity
        } else {
            if #available(iOS 26.0, *) {
                settingsViewController = UIHostingController(
                    rootView: NavigationStack {
                        SettingsView()
                            .environmentObject(settingsPath)
                    }.introspect(.navigationStack, on: .iOS(.v26)) { entity in
                        settingsPath.rootViewController = entity
                    }
                )
            } else {
                settingsViewController = UIHostingController(
                    rootView: NavigationView {
                        SettingsView()
                            .environmentObject(settingsPath)
                    }.introspect(.navigationView(style: .stack), on: .iOS(.v15, .v16, .v17, .v18)) { entity in
                        settingsPath.rootViewController = entity
                    }
                )
            }
        }
        self.settingsPath = settingsPath

        libraryViewController.navigationBar.prefersLargeTitles = true
        browseViewController.navigationBar.prefersLargeTitles = true
        historyViewController.navigationBar.prefersLargeTitles = true
        searchViewController.navigationBar.prefersLargeTitles = true

        if #available(iOS 26.0, *) {
            let searchTab = UISearchTab { _ in
                searchViewController
            }
            searchTab.automaticallyActivatesSearch = true
            let fixedTabs = [
                UITab(
                    title: NSLocalizedString("LIBRARY"),
                    image: UIImage(systemName: "books.vertical.fill"),
                    identifier: "0"
                ) { _ in
                    libraryViewController
                },
                UITab(
                    title: NSLocalizedString("BROWSE"),
                    image: UIImage(systemName: "globe"),
                    identifier: "1"
                ) { _ in
                    browseViewController
                },
                UITab(
                    title: NSLocalizedString("HISTORY"),
                    image: UIImage(systemName: "clock.fill"),
                    identifier: "2"
                ) { _ in
                    historyViewController
                },
                UITab(
                    title: NSLocalizedString("SETTINGS"),
                    image: UIImage(systemName: "gear"),
                    identifier: "3"
                ) { _ in
                    settingsViewController
                }
            ]
            fixedTabs.forEach {
                $0.allowsHiding = false
                $0.preferredPlacement = .fixed
            }
            tabs = fixedTabs + [searchTab]
        } else {
            libraryViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("LIBRARY", comment: ""),
                image: UIImage(systemName: "books.vertical.fill"),
                tag: 0
            )
            browseViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("BROWSE", comment: ""),
                image: UIImage(systemName: "globe"),
                tag: 1
            )
            historyViewController.tabBarItem = UITabBarItem(
                tabBarSystemItem: .history,
                tag: 2
            )
            searchViewController.tabBarItem = UITabBarItem(
                tabBarSystemItem: .search,
                tag: 3
            )
            settingsViewController.tabBarItem = UITabBarItem(
                title: NSLocalizedString("SETTINGS", comment: ""),
                image: UIImage(systemName: "gear"),
                tag: 4
            )
            viewControllers = [
                libraryViewController,
                browseViewController,
                historyViewController,
                searchViewController,
                settingsViewController
            ]
        }

        let updateCount = UserDefaults.standard.integer(forKey: "Browse.updateCount")
        browseViewController.tabBarItem.badgeValue = updateCount > 0 ? String(updateCount) : nil

        NotificationCenter.default.publisher(for: .incognitoMode)
            .sink { [weak self] _ in
                self?.updateFrame(animated: true)
            }
            .store(in: &cancellables)
    }

    func updateFrame(animated: Bool = false) {
        if originalFrame == .zero {
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            originalFrame = view.frame
            shrunkFrame = .init(
                x: originalFrame.origin.x,
                y: originalFrame.origin.y + bannerHeight,
                width: originalFrame.width,
                height: originalFrame.height - bannerHeight
            )
        }
        func commit() {
            if UserDefaults.standard.bool(forKey: "General.incognitoMode") {
                view.frame = shrunkFrame
            } else {
                view.frame = originalFrame
            }
        }
        if animated {
            UIView.animate(withDuration: CATransaction.animationDuration()) {
                commit()
            }
        } else {
            commit()
        }
    }
}

extension TabBarController {
    func showLibraryRefreshView() {
        libraryProgressView.setProgress(value: 0, withAnimation: false)

        if #available(iOS 26.0, *) {
            setBottomAccessory(.init(contentView: libraryRefreshAccessory), animated: true)
        } else {
            libraryRefreshAccessory.layer.opacity = 0
            view.insertSubview(libraryRefreshAccessory, belowSubview: tabBar)
            UIView.animate(withDuration: 0.5) {
                self.libraryRefreshAccessory.layer.opacity = 1
            }
        }
    }

    func setLibraryRefreshProgress(_ progress: Float) {
        libraryProgressView.setProgress(value: progress, withAnimation: true)
    }

    func hideAccessoryView() {
        if #available(iOS 26.0, *) {
            setBottomAccessory(nil, animated: true)
        } else {
            UIView.animate(withDuration: 0.5) {
                self.libraryRefreshAccessory.layer.opacity = 0
            } completion: { _ in
                self.libraryRefreshAccessory.removeFromSuperview()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        if #unavailable(iOS 26.0) {
            let height: CGFloat = 48
            let padding: CGFloat = 16

            libraryRefreshAccessory.frame = CGRect(
                x: tabBar.frame.origin.x + view.safeAreaInsets.left + padding,
                y: tabBar.frame.origin.y - height - padding / 2,
                width: tabBar.frame.width - padding * 2 - view.safeAreaInsets.left - view.safeAreaInsets.right,
                height: height
            )
        }
        updateFrame()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        originalFrame = .init(origin: self.originalFrame.origin, size: size)
        shrunkFrame = self.originalFrame
        coordinator.animate { _ in
            self.view.setNeedsLayout()
        } completion: { _ in
            let bannerHeight = (UIApplication.shared.connectedScenes.first?.delegate as? SceneDelegate)?.totalBannerHeight ?? 0
            self.shrunkFrame = .init(
                x: self.originalFrame.origin.x,
                y: self.originalFrame.origin.y + bannerHeight,
                width: self.originalFrame.width,
                height: self.originalFrame.height - bannerHeight
            )
            self.updateFrame(animated: true)
        }
    }
}

extension TabBarController: UITabBarControllerDelegate {
    @available(iOS 18.0, *)
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        checkForSettingsPop()
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if #unavailable(iOS 18.0) {
            checkForSettingsPop()
        }
    }

    private func checkForSettingsPop() {
        let settingsIndex: Int
        if #available(iOS 26.0, *) {
            settingsIndex = 3
        } else {
            settingsIndex = 4
        }
        if selectedIndex == previousSelectedIndex && previousSelectedIndex == settingsIndex {
            settingsPath?.navigationController?.popToRootViewController(animated: true)
        }
        previousSelectedIndex = selectedIndex
    }
}

// MARK: - Keyboard Shortcuts
extension TabBarController {
    override var keyCommands: [UIKeyCommand]? {
        tabBar.items?.enumerated().map { index, item in
            UIKeyCommand(
                title: item.title ?? "Tab \(index + 1)",
                action: #selector(selectTab),
                input: "\(index + 1)",
                modifierFlags: .shiftOrCommand,
                alternates: [],
                attributes: [],
                state: .off
            )
        }
    }

    @objc private func selectTab(sender: UIKeyCommand) {
        guard
            let input = sender.input,
            let newIndex = Int(input),
            newIndex >= 1 && newIndex <= (tabBar.items?.count ?? 0)
        else { return }
        selectedIndex = newIndex - 1
    }

    override var canBecomeFirstResponder: Bool { true }
}

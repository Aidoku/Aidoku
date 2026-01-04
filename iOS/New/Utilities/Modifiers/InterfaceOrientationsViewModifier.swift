// https://github.com/wvteijlingen/swiftui-interface-orientation

import SwiftUI
import Combine

extension View {
    /// Specifies the interface orientations supported by this view.
    ///
    /// > This modifier requires correct set up of the ``InterfaceOrientationCoordinator``. See documentation for
    /// ``InterfaceOrientationCoordinator``
    ///
    /// ## Multiple orientations
    /// If orientations are specified by multiple views, the allowed orientations for the interface
    /// are defined by the lowest common denominator (i.e. the intersection of all specified orientations).
    ///
    /// For example, given the following code, the only allowed orientation is `.portrait` because that is
    /// the only orientation which is supported by all views:
    ///
    /// ```swift
    /// VStack {
    ///     A().interfaceOrientations([.portrait, .landscape])
    ///     B().interfaceOrientations([.portrait, .portraitUpsideDown])
    /// }
    /// ```
    /// - Parameter orientations: The orientations supported by this view, or `nil` to use default app orientations.
    func interfaceOrientations(_ orientations: UIInterfaceOrientationMask?) -> some View {
        modifier(InterfaceOrientationsViewModifier(orientations: orientations ?? []))
    }
}

private struct InterfaceOrientationsViewModifier: ViewModifier {
    private let orientations: UIInterfaceOrientationMask
    @State private var id = UUID()

    init(orientations: UIInterfaceOrientationMask) {
        self.orientations = orientations
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                if !orientations.isEmpty {
                    InterfaceOrientationCoordinator.shared.register(orientations: orientations, id: id)
                }
            }
            .onDisappear {
                InterfaceOrientationCoordinator.shared.unregister(orientationsWithID: id)
            }
            .onChange(of: orientations) { newValue in
                if orientations.isEmpty {
                    InterfaceOrientationCoordinator.shared.unregister(orientationsWithID: id)
                } else {
                    InterfaceOrientationCoordinator.shared.register(orientations: newValue, id: id)
                }
            }
    }
}

/// A singleton class that coordinates the interface orientations for an entire application.
///
/// ## Usage
/// 1. Create an application delegate using `@UIApplicationDelegateAdaptor`.
/// 2. Implement `application(_:supportedInterfaceOrientationsFor:)` in the application delegate:
///    ```swift
///    private class AppDelegate: NSObject, UIApplicationDelegate {
///      func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
///        InterfaceOrientationCoordinator.shared.supportedOrientations
///      }
///    }
///    ```
/// 3. Use the view modifier `interfaceOrientations(_:)` to specify supported orientations in your SwiftUI view
///    hierarchy:
///    ```swift
///    Text("My View").interfaceOrientations([.portrait, .landscape])
///    ```
public class InterfaceOrientationCoordinator: ObservableObject {
    public static let shared = InterfaceOrientationCoordinator()

    /// The default orientations when no view specifies custom orientations.
    ///
    /// The value of `defaultOrientations` will be loaded from the Info.plist. If the Info.plist cannot be read,
    /// this is set to `.all`.
    public var defaultOrientations: UIInterfaceOrientationMask {
        didSet { resolveOrientations() }
    }

    /// If set to `true`, views are allowed to support orientations that are not specified in `defaultOrientations`.
    ///
    /// For example, if `defaultOrientations` only specifies `.portrait`, but a view specifies `.landscapeLeft`,
    /// the interface will still be allowed to rotate to `.landscapeLeft`.
    public var allowOverridingDefaultOrientations = true {
        didSet { resolveOrientations() }
    }

    /// All the interface orientations that are supported by the SwiftUI view hierarchy that is currently visible.
    public var supportedOrientations: UIInterfaceOrientationMask {
        if orientations.isEmpty {
            return defaultOrientations
        }

        let base: UIInterfaceOrientationMask = allowOverridingDefaultOrientations ? .all : defaultOrientations

        let resolved = orientations.reduce(base) { partialResult, orientation in
            partialResult.intersection(orientation.value)
        }

        if resolved.isEmpty {
            print("Cannot resolve supported interface orientations, 'defaultOrientations' will be used")
            return defaultOrientations
        } else {
            return resolved
        }
    }

    /// The current orientation of the interface.
    ///
    /// This is dependent on the current device orientation and the orientations supported by the SwiftUI
    /// view hierarchy that is currently visible.
    @Published public private(set) var currentOrientation: UIInterfaceOrientation = .unknown

    private var orientations: [UUID: UIInterfaceOrientationMask] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(defaultOrientations: UIInterfaceOrientationMask, allowOverridingDefaultOrientations: Bool = true) {
        self.defaultOrientations = defaultOrientations
        self.allowOverridingDefaultOrientations = allowOverridingDefaultOrientations

        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .sink { _ in
                self.resolveOrientations()
            }
            .store(in: &cancellables)

        resolveOrientations()
    }

    convenience init(allowOverridingDefaultOrientations: Bool = true) {
        let orientationsFromInfoPlist = Bundle.main.infoDictionary?["UISupportedInterfaceOrientations"] as? [String] ?? []

        var defaultOrientations: UIInterfaceOrientationMask = orientationsFromInfoPlist.reduce(into: []) { partialResult, orientation in
            switch orientation {
                case "UIInterfaceOrientationPortrait":
                    partialResult.insert(.portrait)
                case "UIInterfaceOrientationLandscapeLeft":
                    partialResult.insert(.landscapeLeft)
                case "UIInterfaceOrientationLandscapeRight":
                    partialResult.insert(.landscapeRight)
                case "UIInterfaceOrientationPortraitUpsideDown":
                    partialResult.insert(.portraitUpsideDown)
                default:
                    assertionFailure("Unknown value '\(orientation)' for Info.plist entry UISupportedInterfaceOrientations")
            }
        }

        // we needed to disable this in the Info.plist to make it work on ipad, so just add it back here
        if UIDevice.current.userInterfaceIdiom == .pad {
            defaultOrientations.insert(.portraitUpsideDown)
        }

        if defaultOrientations.isEmpty {
            print("Default orientations could not be loaded from Info.plist, defaulting to '.all'")
            self.init(
                defaultOrientations: .all,
                allowOverridingDefaultOrientations: allowOverridingDefaultOrientations
            )
        } else {
            self.init(
                defaultOrientations: defaultOrientations,
                allowOverridingDefaultOrientations: allowOverridingDefaultOrientations
            )
        }
    }

    func register(orientations: UIInterfaceOrientationMask, id: UUID) {
        assert(!orientations.isEmpty, "Using an empty orientation mask is not allowed")

        self.orientations[id] = orientations
        resolveOrientations()
    }

    func unregister(orientationsWithID id: UUID) {
        orientations[id] = nil
        resolveOrientations()
    }

    private func resolveOrientations() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        if #available(iOS 16.0, *) {
            windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        currentOrientation = windowScene.interfaceOrientation
    }
}

//
//  PressableView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import SwiftUI

struct PressableView<V: View>: UIViewRepresentable {
    @Binding var pressed: Bool
    @Binding var releaseAnimationTrigger: Bool

    var content: () -> V

    @Environment(\.isEnabled) private var isEnabled

    init(
        pressed: Binding<Bool>,
        releaseAnimationTrigger: Binding<Bool>,
        content: @escaping () -> V
    ) {
        self._pressed = pressed
        self._releaseAnimationTrigger = releaseAnimationTrigger
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        context.coordinator.hostingController = hostingController

        let touchDownRecognizer = TouchDownGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.onTouchDown(gesture:))
        )
        touchDownRecognizer.cancelsTouchesInView = false
        hostingController.view.addGestureRecognizer(touchDownRecognizer)

        return hostingController.view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.hostingController?.rootView = content()
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: PressableView

        var hostingController: UIHostingController<V>?

        init(_ parent: PressableView) {
            self.parent = parent
        }

        @objc func onTouchDown(gesture: TouchDownGestureRecognizer) {
            switch gesture.state {
                case .began:
                    parent.pressed = true
                case .ended:
                    Task {
                        // sleep for 1ms to fix highlight not working on super fast touches
                        try? await Task.sleep(nanoseconds: 1_000_000)
                        await MainActor.run {
                            withAnimation {
                                parent.pressed = false
                                parent.releaseAnimationTrigger.toggle()
                            }
                        }
                    }
                case .cancelled:
                    parent.pressed = false
                default:
                    break
            }
        }
    }
}

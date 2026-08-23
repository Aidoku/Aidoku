//
//  OnReportScrollVisibilityChange.swift
//  Aidoku
//
//  Created by Skitty on 7/30/25.
//

import SwiftUI

private struct ScrollVisibilityReportingView: UIViewRepresentable {
    @Binding var trigger: Bool
    var action: (Bool) -> Void

    func makeUIView(context: Context) -> ContentView {
        ContentView(action: action)
    }

    func updateUIView(_ uiView: ContentView, context: Context) {
        if trigger {
            uiView.check()
            trigger = false
        }
    }

    class ContentView: UIView {
        var action: ((Bool) -> Void)

        private var storedScrollView: UIScrollView?

        init(action: @escaping ((Bool) -> Void)) {
            self.action = action
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // check visibility in scroll view and report
        func check() {
            guard let scrollView = findScrollView() else { return }
            let frameInScrollView = scrollView.convert(self.frame, from: self.superview)
            let isVisible = scrollView.bounds.intersects(frameInScrollView)
            action(isVisible)
        }

        // find first ancestor scroll view
        private func findScrollView() -> UIScrollView? {
            if let storedScrollView {
                return storedScrollView
            }
            var view: UIView? = self
            while let v = view {
                if let scrollView = v as? UIScrollView {
                    storedScrollView = scrollView
                    return scrollView
                }
                view = v.superview
            }
            return nil
        }
    }
}

extension View {
    func onReportScrollVisibilityChange(trigger: Binding<Bool>, _ action: @escaping (Bool) -> Void) -> some View {
        background(ScrollVisibilityReportingView(trigger: trigger, action: action))
    }
}

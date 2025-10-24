//
//  View.swift
//  Aidoku
//
//  Created by Skitty on 7/21/22.
//

import SwiftUI

struct NoHitTesting: ViewModifier {
    func body(content: Content) -> some View {
        SwiftUIWrapper { content }.allowsHitTesting(false)
    }
}

struct SwiftUIWrapper<T: View>: UIViewControllerRepresentable {
    let content: () -> T
    func makeUIViewController(context: Context) -> UIHostingController<T> {
        UIHostingController(rootView: content())
    }
    func updateUIViewController(_ uiViewController: UIHostingController<T>, context: Context) {}
}

extension View {
    @ViewBuilder
    func userInteractionDisabled(_ disabled: Bool = true) -> some View {
        if disabled {
            self.modifier(NoHitTesting())
        } else {
            self
        }
    }

//    @ViewBuilder
//    func hidden(_ hidden: Bool) -> some View {
//        if hidden {
//            self.hidden()
//        } else {
//            self
//        }
//    }
}

extension View {
    @ViewBuilder
    func offsetListSeparator() -> some View {
        if #available(iOS 16.0, *) {
            self.alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        } else {
            self
        }
    }
}

extension View {
    func scrollClipDisabledPlease() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            return self.scrollClipDisabled()
        } else {
            return self
        }
    }

    func scrollTargetLayoutPlease(isEnabled: Bool = true) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            return self.scrollTargetLayout(isEnabled: isEnabled)
        } else {
            return self
        }
    }

    func scrollViewAlignedPlease() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            return self.scrollTargetBehavior(.viewAligned)
        } else {
            return self
        }
    }

//    func scrollPagingPlease() -> some View {
//        if #available(iOS 17.0, macOS 14.0, *) {
//            return self.scrollTargetBehavior(.paging)
//        } else {
//            return self
//        }
//    }

    func scrollBackgroundHiddenPlease() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            return self.scrollContentBackground(.hidden)
        } else {
            return self.introspect(.scrollView, on: .iOS(.v15)) { scrollView in
                scrollView.backgroundColor = .clear
            }
        }
    }

    func scrollPositionPlease(id: Binding<(some Hashable)?>, anchor: UnitPoint? = nil) -> some View {
        if #available(iOS 17.0, *) {
            return self.scrollPosition(id: id, anchor: anchor)
        } else {
            return self
        }
    }

    func contentTransitionDisabledPlease() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            return self.contentTransition(.identity)
        } else {
            return self
        }
    }

    func listSectionSpacingPlease(_ spacing: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            return self.listSectionSpacing(spacing)
        } else {
            return self
        }
    }

    func scrollDismissesKeyboardInteractively() -> some View {
        if #available(iOS 16.0, *) {
            return self.scrollDismissesKeyboard(.interactively)
        } else {
            return self
        }
    }

    func contentMarginsPlease(
        _ edges: Edge.Set = .all,
        _ length: CGFloat?,
    ) -> some View {
        if #available(iOS 17.0, *) {
            return self.contentMargins(edges, length)
        } else {
            return self
        }

    }

    @ViewBuilder
    func tag<T: Hashable>(_ tag: T, selectable: Bool) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self
                .tag(tag)
                .selectionDisabled(!selectable)
        } else {
            if selectable {
                self.tag(tag)
            } else {
                // not setting a tag makes items not selectable ios <17
                self
            }
        }
    }
}

enum AnimationOptions {
    case linear
    case easeIn
    case easeOut
    case easeInOut
}

extension View {
    static func animate(
        duration: CGFloat,
        options: AnimationOptions = .linear,
        _ execute: @escaping () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            let animation: Animation = switch options {
                case .linear:
                    .linear(duration: duration)
                case .easeIn:
                    .easeIn(duration: duration)
                case .easeOut:
                    .easeOut(duration: duration)
                case .easeInOut:
                    .easeInOut(duration: duration)
            }
            // todo: this has some bugs
//            if #available(iOS 17.0, *) {
//                withAnimation(animation) {
//                    execute()
//                } completion: {
//                    continuation.resume()
//                }
//            } else {
                withAnimation(animation) {
                    execute()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    continuation.resume()
                }
//            }
        }
    }

    func animate(
        duration: CGFloat,
        options: AnimationOptions = .linear,
        _ execute: @escaping () -> Void
    ) async {
        await Self.animate(duration: duration, options: options, execute)
    }
}

extension View {
    /// Focuses next field in sequence, from the given `FocusState`.
    /// Requires a currently active focus state and a next field available in the sequence.
    ///
    /// Example usage:
    /// ```
    /// .onSubmit { self.focusNextField($focusedField) }
    /// ```
    /// Given that `focusField` is an enum that represents the focusable fields. For example:
    /// ```
    /// @FocusState private var focusedField: Field?
    /// enum Field: Int, Hashable {
    ///    case name
    ///    case country
    ///    case city
    /// }
    /// ```
    func focusNextField<F: RawRepresentable>(_ field: FocusState<F?>.Binding) where F.RawValue == Int {
        guard let currentValue = field.wrappedValue else { return }
        let nextValue = currentValue.rawValue + 1
        if let newValue = F(rawValue: nextValue) {
            field.wrappedValue = newValue
        }
    }
}

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension View {
    @ViewBuilder
    func confirmationDialogOrAlert<S, A, M>(
        _ title: S,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> some View where S: StringProtocol, A: View, M: View {
        if #available(iOS 26.0, *) {
            self.alert(
                title,
                isPresented: isPresented,
                actions: actions,
                message: message
            )
        } else {
            self.confirmationDialog(
                title,
                isPresented: isPresented,
                titleVisibility: titleVisibility,
                actions: actions,
                message: message
            )
        }
    }
}

//
//  UIView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/26/22.
//

import UIKit

extension UIView {
//    var parentViewController: UIViewController? {
//        var parentResponder: UIResponder? = self.next
//        while parentResponder != nil {
//            if let viewController = parentResponder as? UIViewController {
//                return viewController
//            }
//            parentResponder = parentResponder?.next
//        }
//        return nil
//    }

    func addOverlay(color: UIColor) {
        let overlay = UIView()
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.frame = bounds
        overlay.backgroundColor = color
        overlay.alpha = 0
        overlay.tag = color.hash
        addSubview(overlay)
    }

    func showOverlay(color: UIColor, alpha: CGFloat = 1) {
        if let overlay = viewWithTag(color.hash) {
            overlay.alpha = alpha
        }
    }

    func hideOverlay(color: UIColor) {
        if let overlay = viewWithTag(color.hash) {
            overlay.alpha = 0
        }
    }
}

extension UIView {
    func forceNoClip() {
        let originalClass: AnyClass = object_getClass(self)!
        let subclassName = "\(originalClass)_ClipsToBoundsSwizzled_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        guard let subclass = objc_allocateClassPair(originalClass, subclassName, 0) else { return }

        let setterSelector = #selector(setter: UIView.clipsToBounds)
        let method = class_getInstanceMethod(UIView.self, setterSelector)!
        let types = method_getTypeEncoding(method)

        let imp: @convention(c) (UIView, Selector, Bool) -> Void = { view, selector, _ in
            let superClass: AnyClass = class_getSuperclass(object_getClass(view))!
            if let superSetter = class_getInstanceMethod(superClass, selector) {
                let superIMP = method_getImplementation(superSetter)
                typealias SetterType = @convention(c) (UIView, Selector, Bool) -> Void
                let casted = unsafeBitCast(superIMP, to: SetterType.self)
                casted(view, selector, false)
            }
        }

        class_replaceMethod(subclass, setterSelector, unsafeBitCast(imp, to: IMP.self), types)
        objc_registerClassPair(subclass)
        object_setClass(self, subclass)
    }
}

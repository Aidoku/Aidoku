//
//  LiquidLensView.swift
//  Aidoku
//
//  Created by Skitty on 12/15/25.
//

import UIKit

// a wrapper for the private _UILiquidLensView class, which UISlider uses on ios 26 for the fancy glass lifting effect

@available(iOS 26.0, *)
class LiquidLensView: UIView {
    private let _lensView: UIView

    var restingBackgroundColor: UIColor = .white {
        didSet {
            _lensView.setValue(restingBackgroundColor, forKey: "restingBackgroundColor")
            let updateRestingBackgroundView = NSSelectorFromString("updateRestingBackgroundView")
            _lensView.perform(updateRestingBackgroundView)
        }
    }

    override init(frame: CGRect) {
        let _UILiquidLensView = NSClassFromString("_UILiquidLensView") as AnyObject as? NSObjectProtocol
        let allocSelector = NSSelectorFromString("alloc")
        let initSelector = NSSelectorFromString("initWithFrame:")

        guard let _UILiquidLensView else {
            self._lensView = .init()
            super.init(frame: frame)
            return
        }

        let alloc = _UILiquidLensView.perform(allocSelector).takeUnretainedValue()
        let instance = alloc.perform(initSelector, with: NSValue(cgRect: .zero)).takeUnretainedValue() as? UIView
        self._lensView = instance ?? .init()

        super.init(frame: frame)

        _lensView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(_lensView)

        NSLayoutConstraint.activate([
            _lensView.topAnchor.constraint(equalTo: topAnchor),
            _lensView.bottomAnchor.constraint(equalTo: bottomAnchor),
            _lensView.leadingAnchor.constraint(equalTo: leadingAnchor),
            _lensView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLifted(_ lifted: Bool, animated: Bool) {
        let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
        typealias SetLifted = @convention(c) (AnyObject, Selector, Bool, Bool, UnsafeRawPointer?, UnsafeRawPointer?) -> Void
        guard let method = _lensView.method(for: selector) else { return }
        let function = unsafeBitCast(method, to: SetLifted.self)
        function(_lensView, selector, lifted, animated, nil, nil)
    }
}

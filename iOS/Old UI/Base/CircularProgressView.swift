//
//  CircularProgressView.swift
//  Aidoku (iOS)
//
//  Created by Brian Dashore on 3/5/22.
//
//  Based off of: https://github.com/leoiphonedev/CircularProgressView-Tutorial

import UIKit

class CircularProgressView: UIView {
    private var progress: CGFloat = 0 {
        willSet(newValue) {
            progressLayer.strokeEnd = newValue
        }
    }
    private var oldProgress: Float = 0 {
        didSet {
            if oldProgress >= 1 {
                oldProgress = 0
            }
        }
    }

    private var progressLayer = CAShapeLayer()
    private var trackLayer = CAShapeLayer()

    lazy var progressColor: UIColor = tintColor ?? .white {
        willSet(newValue) {
            progressLayer.strokeColor = newValue.cgColor
        }
    }
    var trackColor = UIColor.quaternaryLabel {
        willSet(newValue) {
            trackLayer.strokeColor = newValue.cgColor
        }
    }
    var lineWidth: CGFloat = 3
    var radius: CGFloat = 20

    private var progressQueue: [Float] = []
    private var isAnimating = false

    override func draw(_ rect: CGRect) {
        layer.cornerRadius = radius

        let circlePath = UIBezierPath(
            arcCenter: CGPoint(x: frame.size.width / 2, y: frame.size.height / 2),
            radius: (radius * 2 - 1.5) / 2,
            startAngle: -0.5 * .pi,
            endAngle: CGFloat(1.5 * .pi),
            clockwise: true)

        trackLayer.path = circlePath.cgPath
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.strokeColor = trackColor.cgColor
        trackLayer.lineWidth = lineWidth
        trackLayer.strokeEnd = 1
        layer.addSublayer(trackLayer)

        progressLayer.path = circlePath.cgPath
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.strokeEnd = progress
        layer.addSublayer(progressLayer)
    }

    func setProgress(value: Float, withAnimation: Bool) {
        guard value >= oldProgress, value <= 1 else { return }

        if withAnimation {
            progressQueue.append(value)
            startNextAnimationIfNeeded()
        } else {
            progress = CGFloat(value)
            oldProgress = value
            progressQueue.removeAll()
            isAnimating = false
        }
    }

    private func startNextAnimationIfNeeded() {
        guard !isAnimating, !progressQueue.isEmpty else { return }

        let nextValue = progressQueue.removeFirst()

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.duration = 0.5
        animation.fromValue = oldProgress
        animation.toValue = nextValue
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.delegate = self
        progressLayer.add(animation, forKey: "animateProgress")

        CATransaction.setDisableActions(true)
        progress = CGFloat(nextValue)
        CATransaction.setDisableActions(false)

        oldProgress = nextValue
        isAnimating = true
    }
}

extension CircularProgressView: CAAnimationDelegate {
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        isAnimating = false
        startNextAnimationIfNeeded()
    }
}

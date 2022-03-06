//
//  CircularProgressView.swift
//  Aidoku (iOS)
//
//  Created by Brian Dashore on 3/5/22.
//
//  Based off of: https://github.com/leoiphonedev/CircularProgressView-Tutorial

import UIKit

class CircularProgressView: UIView {
    // You can set this value directly, but it's better to use setProgress
    var progress: CGFloat = 0 {
        didSet(newValue) {
            progressLayer.strokeEnd = newValue
        }
    }

    private var progressLayer = CAShapeLayer()
    private var trackLayer = CAShapeLayer()

    var progressColor = UIColor.white {
        didSet(newValue) {
            progressLayer.strokeColor = newValue.cgColor
        }
    }
    var trackColor = UIColor.white {
        didSet(newValue) {
            trackLayer.strokeColor = newValue.cgColor
        }
    }
    var lineWidth: CGFloat = 3

    override func draw(_ rect: CGRect) {
        self.backgroundColor = UIColor.clear
        self.layer.cornerRadius = self.frame.size.width / 2

        let circlePath = UIBezierPath(
            arcCenter: CGPoint(x: frame.size.width / 2, y: frame.size.height / 2),
            radius: (frame.size.width - 1.5) / 2,
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
        if withAnimation {
            let endAnimation = CABasicAnimation(keyPath: "strokeEnd")
            endAnimation.duration = 1
            endAnimation.fromValue = 0
            endAnimation.toValue = value
            endAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
            progressLayer.add(endAnimation, forKey: "animateProgress")
        }

        progress = CGFloat(value)
    }
}

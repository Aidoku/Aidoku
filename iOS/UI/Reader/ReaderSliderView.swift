//
//  ReaderSliderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/20/22.
//

import UIKit

class ReaderSliderView: UIControl {

    enum SliderDirection {
        case forward
        case backward
    }

    var direction: SliderDirection = .forward {
        didSet {
            thumbPositionConstraint?.isActive = false
            trackPositionConstraint?.isActive = false
            if direction == .forward {
                thumbPositionConstraint = thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -10)
                trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5)
            } else {
                thumbPositionConstraint = thumbView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
                trackPositionConstraint = progressedTrackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)
            }
            thumbPositionConstraint?.isActive = true
            trackPositionConstraint?.isActive = true
        }
    }

    var minimumValue: CGFloat = 0
    var maximumValue: CGFloat = 1
    var currentValue: CGFloat = 0 {
        didSet {
            updateLayerFrames()
        }
    }

    let trackView = UIView()
    let progressedTrackView = UIView()
    let thumbView = UIView()

    private var trackWidthConstraint: NSLayoutConstraint?
    private var trackPositionConstraint: NSLayoutConstraint?
    private var thumbPositionConstraint: NSLayoutConstraint?

    private var previousLocation = CGPoint()

    override var frame: CGRect {
        didSet {
            updateLayerFrames()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        trackView.backgroundColor = .secondarySystemFill
        trackView.layer.cornerRadius = 1.5
        trackView.isUserInteractionEnabled = false
        trackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trackView)

        progressedTrackView.backgroundColor = tintColor
        progressedTrackView.layer.cornerRadius = 1.5
        progressedTrackView.isUserInteractionEnabled = false
        progressedTrackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressedTrackView)

        thumbView.backgroundColor = .white
        thumbView.layer.shadowPath = UIBezierPath(rect: thumbView.bounds).cgPath
        thumbView.layer.shadowRadius = 1.5
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 1)
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOpacity = 0.2
        thumbView.layer.cornerRadius = 15
        thumbView.isUserInteractionEnabled = false
        thumbView.transform = CGAffineTransform(scaleX: 1/3, y: 1/3)
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbView)

        trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5).isActive = true
        trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5).isActive = true
        trackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        trackView.heightAnchor.constraint(equalToConstant: 3).isActive = true

        trackWidthConstraint = progressedTrackView.widthAnchor.constraint(equalToConstant: 5)
        trackWidthConstraint?.isActive = true
        trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5)
        trackPositionConstraint?.isActive = true
        progressedTrackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        progressedTrackView.heightAnchor.constraint(equalToConstant: 3).isActive = true

        thumbPositionConstraint = thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -10)
        thumbPositionConstraint?.isActive = true
        thumbView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        thumbView.heightAnchor.constraint(equalToConstant: 30).isActive = true
        thumbView.widthAnchor.constraint(equalToConstant: 30).isActive = true

        updateLayerFrames()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        updateLayerFrames()
    }

    private func updateLayerFrames() {
        let position = positionForValue(currentValue)
        if direction == .forward {
            trackWidthConstraint?.constant = position - trackView.frame.origin.x
            thumbPositionConstraint?.constant =  position - thumbView.bounds.width / 2
        } else {
            trackWidthConstraint?.constant = trackView.bounds.width - position - trackView.frame.origin.x
            thumbPositionConstraint?.constant =  position - trackView.bounds.width + thumbView.bounds.width / 2
        }
    }

    // TODO: animate this
    func move(toValue value: CGFloat) {
        currentValue = value
    }

    func positionForValue(_ value: CGFloat) -> CGFloat {
        if direction == .forward {
            return trackView.bounds.width * value + trackView.frame.origin.x
        } else {
            return trackView.bounds.width - (trackView.bounds.width * value) - trackView.frame.origin.x
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        previousLocation = touch.location(in: self)

        if thumbView.frame.contains(previousLocation) {
            thumbView.tag = 1
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                self.thumbView.transform = CGAffineTransform(scaleX: 1/2, y: 1/2)
            }
            return true
        }

        return false
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)

        let deltaLocation = location.x - previousLocation.x
        let deltaValue = (maximumValue - minimumValue) * deltaLocation / bounds.width

        previousLocation = location

        if thumbView.tag == 1 {
            if direction == .forward {
                currentValue += deltaValue
            } else {
                currentValue -= deltaValue
            }
            currentValue = boundValue(currentValue, toLowerValue: minimumValue, upperValue: maximumValue)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        updateLayerFrames()

        CATransaction.commit()

        sendActions(for: .valueChanged)

        return true
    }

    private func boundValue(_ value: CGFloat, toLowerValue lowerValue: CGFloat, upperValue: CGFloat) -> CGFloat {
        min(max(value, lowerValue), upperValue)
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        thumbView.tag = 0
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            self.thumbView.transform = CGAffineTransform(scaleX: 1/3, y: 1/3)
        }
        sendActions(for: .editingDidEnd)
    }
}

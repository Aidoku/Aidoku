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
                thumbPositionConstraint = thumbView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 10)
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

    private let trackView = UIView()
    private let progressedTrackView = UIView()
    private let thumbView = UIView()
    private let grabberView = UIView(frame: .init(x: 0, y: 0, width: 10, height: 10))

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
        configure()
        constrain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        updateLayerFrames()
    }

    func configure() {
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

        thumbView.isUserInteractionEnabled = false
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbView)

        grabberView.backgroundColor = .white
        grabberView.layer.shadowPath = UIBezierPath(roundedRect: grabberView.bounds, cornerRadius: 5).cgPath
        grabberView.layer.shadowRadius = 1.5
        grabberView.layer.shadowOffset = CGSize(width: 0, height: 1)
        grabberView.layer.shadowColor = UIColor.black.cgColor
        grabberView.layer.shadowOpacity = 0.1
        grabberView.layer.cornerRadius = 5
        grabberView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(grabberView)
    }

    func constrain() {
        trackWidthConstraint = progressedTrackView.widthAnchor.constraint(equalToConstant: 5)
        trackWidthConstraint?.isActive = true
        trackPositionConstraint = progressedTrackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5)
        trackPositionConstraint?.isActive = true
        thumbPositionConstraint = thumbView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -10)
        thumbPositionConstraint?.isActive = true

        NSLayoutConstraint.activate([
            trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            trackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trackView.heightAnchor.constraint(equalToConstant: 3),

            progressedTrackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressedTrackView.heightAnchor.constraint(equalToConstant: 3),

            thumbView.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumbView.heightAnchor.constraint(equalToConstant: 30),
            thumbView.widthAnchor.constraint(equalToConstant: 30),

            grabberView.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            grabberView.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor),
            grabberView.heightAnchor.constraint(equalToConstant: 10),
            grabberView.widthAnchor.constraint(equalToConstant: 10)
        ])
    }

    override func tintColorDidChange() {
        progressedTrackView.backgroundColor = tintColor
    }

    private func updateLayerFrames() {
        guard trackView.frame.size != .zero else { return }
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
                self.grabberView.transform = CGAffineTransform(scaleX: 3/2, y: 3/2)
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
            self.grabberView.transform = .identity
        }
        sendActions(for: .editingDidEnd)
    }
}

//
//  ReaderSliderView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/20/22.
//

import UIKit

class ReaderSliderView: UIControl {
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
    private var thumbTrailingConstraint: NSLayoutConstraint?
    
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
        
        progressedTrackView.backgroundColor = .systemBlue
        progressedTrackView.layer.cornerRadius = 1.5
        progressedTrackView.isUserInteractionEnabled = false
        progressedTrackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressedTrackView)

        thumbView.backgroundColor = .white
        thumbView.layer.shadowRadius = 1.5
        thumbView.layer.shadowOffset = CGSize(width: 0, height: 1)
        thumbView.layer.shadowColor = UIColor.black.cgColor
        thumbView.layer.shadowOpacity = 0.2
        thumbView.layer.cornerRadius = 5
        thumbView.isUserInteractionEnabled = false
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbView)
        
        trackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5).isActive = true
        trackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5).isActive = true
        trackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        trackView.heightAnchor.constraint(equalToConstant: 3).isActive = true
        
        trackWidthConstraint = progressedTrackView.widthAnchor.constraint(equalToConstant: 5)
        trackWidthConstraint?.isActive = true
        progressedTrackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5).isActive = true
        progressedTrackView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        progressedTrackView.heightAnchor.constraint(equalToConstant: 3).isActive = true
        
        thumbTrailingConstraint = thumbView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)
        thumbTrailingConstraint?.isActive = true
        thumbView.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        thumbView.heightAnchor.constraint(equalToConstant: 10).isActive = true
        thumbView.widthAnchor.constraint(equalToConstant: 10).isActive = true
        
        updateLayerFrames()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        updateLayerFrames()
    }
    
    private func updateLayerFrames() {
        let origin = thumbOriginForValue(currentValue)
        trackWidthConstraint?.constant = trackView.bounds.width - origin.x
        thumbTrailingConstraint?.constant = 0 - (trackView.bounds.width - origin.x)
    }
    
    func positionForValue(_ value: CGFloat) -> CGFloat {
        trackView.bounds.width - (trackView.bounds.width * value) + trackView.frame.origin.x
    }
    
    private func thumbOriginForValue(_ value: CGFloat) -> CGPoint {
        let x = positionForValue(value) - thumbView.bounds.size.width / 2.0
        return CGPoint(x: x, y: (bounds.height - thumbView.bounds.size.height) / 2.0)
    }
    
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        previousLocation = touch.location(in: self)
        
        if thumbView.frame.contains(previousLocation) {
            thumbView.tag = 1
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
            currentValue -= deltaValue
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
        sendActions(for: .editingDidEnd)
    }
}

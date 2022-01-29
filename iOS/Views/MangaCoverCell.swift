//
//  MangaCoverCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/23/22.
//

import UIKit
import Kingfisher

class MangaCoverCell: UICollectionViewCell {
    
    var manga: Manga? {
        didSet {
            layoutViews()
        }
    }
    var imageView = UIImageView()
    var titleLabel = UILabel()
    var gradient = CAGradientLayer()
    
    var highlightView = UIView()
    
    init(manga: Manga) {
        super.init(frame: .zero)
        self.manga = manga
        layoutViews()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        gradient.frame = bounds
    }
    
    func layoutViews() {
        for view in subviews {
            view.removeFromSuperview()
        }
        
        layer.cornerRadius = 5
        
        layer.borderWidth = 1
        layer.borderColor = UIColor.quaternarySystemFill.cgColor
        
        let processor = DownsamplingImageProcessor(size: bounds.size) //|> RoundCornerImageProcessor(cornerRadius: 5)
        let retry = DelayRetryStrategy(maxRetryCount: 5, retryInterval: .seconds(0.5))
        imageView.kf.setImage(
            with: URL(string: manga?.cover ?? ""),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: [
                .processor(processor),
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(0.3)),
                .retryStrategy(retry),
                .cacheOriginalImage
            ]
        )
        imageView.layer.cornerRadius = layer.cornerRadius
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        gradient.frame = bounds
        gradient.locations = [0.6, 1]
        gradient.colors = [
            UIColor(white: 0, alpha: 0).cgColor,
            UIColor(white: 0, alpha: 0.7).cgColor
        ]
        gradient.cornerRadius = layer.cornerRadius
        
        let overlayView = UIView()
        overlayView.layer.insertSublayer(gradient, at: 0)
        overlayView.layer.cornerRadius = layer.cornerRadius
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)
        
        titleLabel.text = manga?.title ?? "No Title"
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        highlightView.backgroundColor = UIColor(white: 0, alpha: 0.5)
        highlightView.alpha = 0
        highlightView.layer.cornerRadius = layer.cornerRadius
        highlightView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightView)
        
        imageView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        imageView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
        
        overlayView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        overlayView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
        
        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8).isActive = true
        titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8).isActive = true
        titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8).isActive = true
        
        highlightView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        highlightView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
    }
    
    func highlight() {
        highlightView.alpha = 1
    }
    
    func unhighlight(animated: Bool = true) {
        UIView.animate(withDuration: animated ? 0.3 : 0) {
            self.highlightView.alpha = 0
        }
    }
}

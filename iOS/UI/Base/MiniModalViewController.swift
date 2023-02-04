//
//  MiniModalViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/12/22.
//

import UIKit

protocol MiniModalDelegate: AnyObject {
    func modalWillDismiss()
}

class MiniModalViewController: UIViewController {

    weak var delegate: MiniModalDelegate?

    var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return view
    }()

    lazy var dimmedView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        view.alpha = maxDimmedAlpha
        return view
    }()

    let scrollView = UIScrollView()

    let maxDimmedAlpha: CGFloat = 0.6
    var maxHeight: CGFloat = UIScreen.main.bounds.height - 64 - 30

    var containerViewMaxHeightConstraint: NSLayoutConstraint?
    var containerViewHeightConstraint: NSLayoutConstraint?
    var containerViewBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        dimmedView.translatesAutoresizingMaskIntoConstraints = false
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmedView)
        view.addSubview(containerView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)

        activateConstraints()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(animateDismissView))
        dimmedView.addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(self.handlePanGesture(gesture:)))
        panGesture.delaysTouchesBegan = false
        panGesture.delaysTouchesEnded = false
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dimmedView.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        containerViewBottomConstraint?.constant = scrollView.bounds.size.height
        animateShowDimmedView()
        animatePresentContainer()
    }

    func activateConstraints() {
        NSLayoutConstraint.activate([
            dimmedView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmedView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmedView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmedView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        containerViewMaxHeightConstraint = containerView.heightAnchor.constraint(lessThanOrEqualToConstant: maxHeight)
        containerViewHeightConstraint = containerView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        containerViewBottomConstraint = containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 500)
        containerViewHeightConstraint?.isActive = true
        containerViewBottomConstraint?.isActive = true
        containerViewMaxHeightConstraint?.isActive = true
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            self.maxHeight = UIScreen.main.bounds.height - 64 - 30
            self.containerViewMaxHeightConstraint?.constant = self.maxHeight
        }
    }

    @objc func handlePanGesture(gesture: UIPanGestureRecognizer) {
        let velocity = gesture.velocity(in: view)
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            if translation.y < 0 {
                containerViewHeightConstraint?.constant = sqrt(-translation.y)
            } else {
                containerViewHeightConstraint?.constant = -translation.y
            }
        case .ended:
            if (translation.y > 100 && velocity.y > 1) || velocity.y > 1000 {
                animateDismissView()
            } else {
                animatePresentContainer()
            }
            if velocity.y < 0 {
                scrollView.isScrollEnabled = true
            }
        default:
            break
        }
    }

    func animatePresentContainer() {
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
            self.containerViewHeightConstraint?.constant = 0
            self.containerViewBottomConstraint?.constant = 0
            self.view.layoutIfNeeded()
        }
    }

    func animateShowDimmedView() {
        dimmedView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.dimmedView.alpha = self.maxDimmedAlpha
        }
    }

    @objc func animateDismissView() {
        delegate?.modalWillDismiss()

        dimmedView.alpha = maxDimmedAlpha
        UIView.animate(withDuration: 0.3) {
            self.dimmedView.alpha = 0

            self.containerViewBottomConstraint?.constant = self.scrollView.bounds.size.height - (self.containerViewHeightConstraint?.constant ?? 0)
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.dismiss(animated: false)
        }
    }
}

// MARK: - Gesture Recognizer Delegate
extension MiniModalViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if let gesture = gestureRecognizer as? UIPanGestureRecognizer {
            let direction = gesture.velocity(in: containerView).y

            if containerView.bounds.size.height == maxHeight && scrollView.contentOffset.y <= 0 && direction > 0 {
                scrollView.isScrollEnabled = false
            } else {
                scrollView.isScrollEnabled = true
            }
        }

        return false
    }
}

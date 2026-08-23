//
//  FilterModalViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/13/22.
//

import UIKit

class SelectedFilters {
    var filters: [FilterBase] = []
}

class FilterModalViewController: MiniModalViewController {

    let filters: [FilterBase]
    var selectedFilters: SelectedFilters

    var stackView: FilterStackView?

    let toolbarView = UIView()
    let resetButton = UIButton(type: .roundedRect)
    let doneButton = UIButton(type: .roundedRect)

    let bottomInset = UIApplication.shared.firstKeyWindow?.safeAreaInsets.bottom ?? 0

    lazy var scrollViewUpperHeightConstraint: NSLayoutConstraint = {
        let constraint = scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: UIScreen.main.bounds.height - 64)
        constraint.priority = .defaultHigh
        return constraint
    }()

    init(filters: [FilterBase], selectedFilters: SelectedFilters) {
        self.filters = filters
        self.selectedFilters = selectedFilters

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.delaysContentTouches = false

        stackView = FilterStackView(filters: filters.filter({ !($0 is TextFilter) }), selectedFilters: selectedFilters)
        stackView?.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView!)

        toolbarView.backgroundColor = .secondarySystemGroupedBackground
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(toolbarView)

        let separatorView = UIView()
        separatorView.backgroundColor = .separator
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(separatorView)

        resetButton.setTitle(NSLocalizedString("RESET", comment: ""), for: .normal)
        resetButton.addTarget(self, action: #selector(animateDismissView), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(resetButton)

        doneButton.setTitle(NSLocalizedString("BUTTON_FILTER", comment: ""), for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.addTarget(self, action: #selector(animateDismissView), for: .touchUpInside)
        doneButton.backgroundColor = view.tintColor
        doneButton.layer.cornerRadius = 8
        doneButton.layer.cornerCurve = .continuous
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(doneButton)

        scrollView.topAnchor.constraint(equalTo: containerView.topAnchor).isActive = true

        scrollViewUpperHeightConstraint.isActive = true

        let two = scrollView.heightAnchor.constraint(equalTo: stackView!.heightAnchor, constant: 25 + 60 + bottomInset)
        two.priority = .defaultLow
        two.isActive = true

        scrollView.widthAnchor.constraint(equalTo: containerView.widthAnchor).isActive = true

        stackView?.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 15).isActive = true
        stackView?.widthAnchor.constraint(equalTo: containerView.widthAnchor).isActive = true

        toolbarView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor).isActive = true
        toolbarView.widthAnchor.constraint(equalTo: containerView.widthAnchor).isActive = true
        toolbarView.heightAnchor.constraint(equalToConstant: 60 + bottomInset).isActive = true

        separatorView.topAnchor.constraint(equalTo: toolbarView.topAnchor).isActive = true
        separatorView.widthAnchor.constraint(equalTo: toolbarView.widthAnchor).isActive = true
        separatorView.heightAnchor.constraint(equalToConstant: 0.5).isActive = true

        resetButton.leadingAnchor.constraint(equalTo: toolbarView.safeAreaLayoutGuide.leadingAnchor, constant: 22).isActive = true
        resetButton.topAnchor.constraint(equalTo: toolbarView.topAnchor, constant: 15).isActive = true
        resetButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        doneButton.trailingAnchor.constraint(equalTo: toolbarView.safeAreaLayoutGuide.trailingAnchor, constant: -22).isActive = true
        doneButton.topAnchor.constraint(equalTo: toolbarView.topAnchor, constant: 15).isActive = true

        doneButton.widthAnchor.constraint(equalToConstant: 80).isActive = true
        doneButton.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSize()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: nil) { _ in
            self.scrollViewUpperHeightConstraint.constant = UIScreen.main.bounds.height - 64
            self.updateContentSize()
        }
    }

    func updateContentSize() {
        scrollView.contentSize = CGSize(
            width: scrollView.bounds.width,
            height: (stackView?.bounds.size.height ?? 0) + 25 + 60
        )
    }
}

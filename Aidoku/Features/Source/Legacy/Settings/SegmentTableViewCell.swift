//
//  SegmentTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/27/22.
//

import Combine
import UIKit

class SegmentTableViewCell: UITableViewCell {

    var segmentedControl: UISegmentedControl

    var source: Source?

    var item: SettingItem? {
        didSet {
            segmentedControl = UISegmentedControl(items: item?.values ?? [])
            if let key = item?.key {
                segmentedControl.selectedSegmentIndex = UserDefaults.standard.integer(forKey: key)
            }
        }
    }

    var segmentedLeadingConstraint: NSLayoutConstraint?

    private var cancellables = Set<AnyCancellable>()

    init(source: Source? = nil, item: SettingItem? = nil, reuseIdentifier: String?) {
        self.source = source
        self.item = item
        segmentedControl = UISegmentedControl(items: item?.values ?? [])
        if let key = item?.key {
            segmentedControl.selectedSegmentIndex = UserDefaults.standard.integer(forKey: key)
        }
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        activateConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activateConstraints() {
        selectionStyle = .none
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(segmentedControl)

        segmentedControl.addTarget(self, action: #selector(valueChanged), for: .valueChanged)

        if let requires = item?.requires {
            segmentedControl.isEnabled = UserDefaults.standard.bool(forKey: requires)
            NotificationCenter.default.publisher(for: Notification.Name(requires))
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.segmentedControl.isEnabled = UserDefaults.standard.bool(forKey: requires)
                    }
                }
                .store(in: &cancellables)
        } else if let requires = item?.requiresFalse {
            segmentedControl.isEnabled = !UserDefaults.standard.bool(forKey: requires)
            NotificationCenter.default.publisher(for: Notification.Name(requires))
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.segmentedControl.isEnabled = !UserDefaults.standard.bool(forKey: requires)
                    }
                }
                .store(in: &cancellables)
        }

        if item?.title == nil {
            segmentedLeadingConstraint = segmentedControl.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor)
            segmentedLeadingConstraint?.isActive = true
        }

        NSLayoutConstraint.activate([
            segmentedControl.heightAnchor.constraint(equalToConstant: 29),
            segmentedControl.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            segmentedControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    @objc func valueChanged() {
        if let key = item?.key {
            UserDefaults.standard.set(segmentedControl.selectedSegmentIndex, forKey: key)
            if let source = source, let notification = item?.notification {
                source.performAction(key: notification)
            }
            NotificationCenter.default.post(name: Notification.Name(key), object: nil)
        }
    }
}

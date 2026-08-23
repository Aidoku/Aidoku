//
//  BaseTableViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 12/30/22.
//

import UIKit

class BaseTableViewController: BaseObservingViewController, UITableViewDelegate {

    lazy var tableView = UITableView(frame: .zero, style: tableViewStyle)

    var tableViewStyle: UITableView.Style {
        .insetGrouped
    }

    override func configure() {
        tableView.delegate = self
        tableView.delaysContentTouches = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }

    override func constrain() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor)
        ])
    }
}

//
//  SourceSettingSelectViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/16/22.
//

import UIKit

class SourceSettingSelectViewController: UITableViewController {
    
    let source: Source
    let item: SourceSettingItem
    
    var multi: Bool {
        item.type == "multi-select"
    }
    
    // single
    var value: String {
        get {
            UserDefaults.standard.string(forKey: "\(source.id).\(item.key ?? "")") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "\(source.id).\(item.key ?? "")")
        }
    }
    var index: Int {
        item.values?.firstIndex(of: value) ?? -1
    }
    
    // multi
    var values: [String] {
        get {
            (UserDefaults.standard.array(forKey: "\(source.id).\(item.key ?? "")") as? [String]) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "\(source.id).\(item.key ?? "")")
        }
    }
    var indexes: [Int] {
        var indexes = [Int]()
        for value in values {
            if let index = item.values?.firstIndex(of: value) {
                indexes.append(index)
            }
        }
        return indexes
    }
    
    init(source: Source, item: SourceSettingItem) {
        self.source = source
        self.item = item
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = item.title
        
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0.0
        }
        tableView.delaysContentTouches = false
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
    }
}

// MARK: - Table View Data Source
extension SourceSettingSelectViewController {
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        item.values?.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        item.footer
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
        
        if indexPath.row < item.titles?.count ?? 0 {
            cell.textLabel?.text = item.titles?[indexPath.row]
            cell.accessoryType = .none
            if multi {
                if indexes.contains(indexPath.row) {
                    cell.accessoryType = .checkmark
                }
            } else if index == indexPath.row {
                cell.accessoryType = .checkmark
            }
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if multi {
            if let cell = tableView.cellForRow(at: indexPath), let itemValues = item.values {
                if cell.accessoryType == .checkmark {
                    cell.accessoryType = .none
                    values.removeAll(where: { $0 == itemValues[indexPath.row] })
                } else {
                    cell.accessoryType = .checkmark
                    values.append(itemValues[indexPath.row])
                }
            }
        } else {
            if let values = item.values, indexPath.row < values.count {
                tableView.cellForRow(at: IndexPath(row: index, section: 0))?.accessoryType = .none
                tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark
                value = values[indexPath.row]
            }
        }
        if let notification = item.notification {
            source.performAction(key: notification)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

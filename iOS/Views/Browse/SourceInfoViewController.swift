//
//  SourceInfoViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/15/22.
//

import UIKit
import Kingfisher

// MARK: - Header View
class SourceInfoHeaderView: UIView {
    
    var source: Source
    
    let iconSize: CGFloat = 48
    
    let contentView = UIView()
    let iconView = UIImageView()
    let labelStack = UIStackView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let uninstallButton = UIButton(type: .roundedRect)
    
    init(source: Source) {
        self.source = source
        super.init(frame: .zero)
        layoutViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func layoutViews() {
        
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        
        iconView.kf.setImage(
            with: source.url.appendingPathComponent("Icon.png"),
            placeholder: UIImage(named: "MangaPlaceholder"),
            options: nil
        )
        iconView.layer.borderColor = UIColor.quaternarySystemFill.cgColor
        iconView.layer.borderWidth = 1
        iconView.layer.cornerRadius = iconSize * 0.225
        iconView.layer.cornerCurve = .continuous
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        
        labelStack.axis = .vertical
        labelStack.distribution = .equalSpacing
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(labelStack)
        
        titleLabel.text = source.info.name
        labelStack.addArrangedSubview(titleLabel)
        
        subtitleLabel.text = source.info.id
        subtitleLabel.textColor = .secondaryLabel
        labelStack.addArrangedSubview(subtitleLabel)
        
//        uninstallButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
//        uninstallButton.setTitle("UNINSTALL", for: .normal)
//        uninstallButton.setTitleColor(.white, for: .normal)
//        uninstallButton.layer.cornerRadius = 14
//        uninstallButton.backgroundColor = tintColor
        uninstallButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(uninstallButton)
        
        activateConstraints()
    }
    
    func activateConstraints() {
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            contentView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            contentView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            
            labelStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            labelStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            
            uninstallButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            uninstallButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            uninstallButton.widthAnchor.constraint(equalToConstant: uninstallButton.intrinsicContentSize.width + 24),
            uninstallButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
}

// MARK: - View Controller
class SourceInfoViewController: UITableViewController {
    
    var source: Source
    
    init(source: Source) {
        self.source = source
        super.init(style: .insetGrouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Source Info"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0.0
        }
        tableView.delaysContentTouches = false
        tableView.keyboardDismissMode = .onDrag
        
        let headerView = SourceInfoHeaderView(source: source)
        headerView.frame.size.height = 48 + 32 + 20
        tableView.tableHeaderView = headerView
        
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "UITableViewCell")
        tableView.register(TextInputTableViewCell.self, forCellReuseIdentifier: "TextInputTableViewCell")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        source.needsFilterRefresh = true
    }
    
    @objc func close() {
        dismiss(animated: true)
    }
}

// MARK: - Table View Data Source
extension SourceInfoViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + source.settingItems.count + (source.languages.isEmpty ? 0 : 1)
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !source.languages.isEmpty && section == 0 {
            return 1
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return 2
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].items?.count ?? 0
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !source.languages.isEmpty && section == 0 {
            return "Language"
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return "Info"
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].title
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if !source.languages.isEmpty && section == 0 {
            return nil
        } else if source.settingItems.isEmpty || section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            return nil
        }
        return source.settingItems[section + (source.languages.isEmpty ? 0 : -1)].footer
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if !source.languages.isEmpty && indexPath.section == 0 {
            var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell.Value1")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            }
            
            cell?.textLabel?.text = "Language"
            if let value = UserDefaults.standard.string(forKey: "\(source.id)._language"),
               let index = source.languages.firstIndex(of: value) {
                cell?.detailTextLabel?.text = source.languages[index]
            }
            cell?.accessoryType = .disclosureIndicator
            
            return cell!
        } else if source.settingItems.isEmpty || indexPath.section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell.Value1")
            if cell == nil {
                cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            }
            
            switch indexPath.row {
            case 0:
                cell?.textLabel?.text = "Version"
                cell?.detailTextLabel?.text = String(source.info.version)
            case 1:
                cell?.textLabel?.text = "Language"
                cell?.detailTextLabel?.text = source.info.lang
            default:
                break
            }
            
            cell?.accessoryType = .none
            cell?.selectionStyle = .none
            
            return cell!
        } else if let item = source.settingItems[indexPath.section + (source.languages.isEmpty ? 0 : -1)].items?[indexPath.row] {
            let cell: UITableViewCell
            switch item.type {
            case "select":
                cell = UITableViewCell(style: .value1, reuseIdentifier: "UITableViewCell.Value1")
            case "switch":
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UITableViewCell.Subtitle")
                cell.detailTextLabel?.textColor = .secondaryLabel
            case "text":
                cell = TextInputTableViewCell(source: source, reuseIdentifier: "TextInputTableViewCell")
            default:
                cell = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell", for: indexPath)
            }
            
            cell.textLabel?.text = item.title
            
            if item.type == "select" {
                if let value = UserDefaults.standard.string(forKey: "\(source.id).\(item.key ?? "")"),
                   let index = item.values?.firstIndex(of: value) {
                    cell.detailTextLabel?.text = item.titles?[index]
                }
                cell.accessoryType = .disclosureIndicator
            } else if item.type == "multi-select" {
                cell.accessoryType = .disclosureIndicator
            } else if item.type == "switch" {
                cell.detailTextLabel?.text = item.subtitle
                let switchView = UISwitch()
                switchView.defaultsKey = "\(source.id).\(item.key ?? "")"
                cell.accessoryView = switchView
                cell.selectionStyle = .none
            } else if item.type == "button" {
                cell.textLabel?.textColor = view.tintColor
            } else if item.type == "text" {
                (cell as? TextInputTableViewCell)?.item = item
            }
            
            return cell
        }
        
        return UITableViewCell()
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !source.languages.isEmpty && indexPath.section == 0 {
            let item = SourceSettingItem(type: "select", key: "_language", title: "Language", values: source.languages, titles: source.languages)
            navigationController?.pushViewController(SourceSettingSelectViewController(source: source, item: item), animated: true)
        } else if source.settingItems.isEmpty || indexPath.section == source.settingItems.count + (source.languages.isEmpty ? 0 : 1) {
            // info
        } else if let item = source.settingItems[indexPath.section + (source.languages.isEmpty ? 0 : -1)].items?[indexPath.row] {
            if item.type == "select" || item.type == "multi-select" {
                navigationController?.pushViewController(SourceSettingSelectViewController(source: source, item: item), animated: true)
            } else if item.type == "button" {
                if let key = item.action {
                    source.performAction(key: key)
                }
            }
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

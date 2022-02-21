//
//  TextInputTableViewCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 2/16/22.
//

import UIKit

class TextInputTableViewCell: UITableViewCell {

    let textField: UITextField = {
        let textField = UITextField()
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    let source: Source

    var placeholder: String? {
        didSet {
            textField.placeholder = placeholder
        }
    }

    var item: SourceSettingItem? {
        didSet {
            placeholder = item?.placeholder
            textField.text = UserDefaults.standard.string(forKey: "\(source.id).\(item?.key ?? "")")
        }
    }

    init(source: Source, reuseIdentifier: String?) {
        self.source = source
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        activateConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activateConstraints() {
        selectionStyle = .none
        textField.delegate = self
        contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.heightAnchor.constraint(equalToConstant: 22),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11)
        ])
    }
}

// MARK: - Text Field Delegate
extension TextInputTableViewCell: UITextFieldDelegate {

    func textFieldDidEndEditing(_ textField: UITextField) {
        if let key = item?.key {
            UserDefaults.standard.set(textField.text, forKey: "\(source.id).\(key)")
            if let notification = item?.notification {
                source.performAction(key: notification)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

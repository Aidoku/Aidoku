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

    var source: Source?

    var placeholder: String? {
        didSet {
            textField.placeholder = placeholder
        }
    }

    var item: SettingItem? {
        didSet {
            configureTextField()
        }
    }

    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init(source: Source? = nil, reuseIdentifier: String?) {
        self.source = source
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        activateConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureTextField() {
        placeholder = item?.placeholder
        textField.text = UserDefaults.standard.string(forKey: item?.key ?? "")
        if let value = item?.autocapitalizationType,
           let autocapitalizationType = UITextAutocapitalizationType(rawValue: value) {
            textField.autocapitalizationType = autocapitalizationType
        }
        if let value = item?.autocorrectionType,
           let autocorrectionType = UITextAutocorrectionType(rawValue: value) {
            textField.autocorrectionType = autocorrectionType
        }
        if let value = item?.spellCheckingType,
           let spellCheckingType = UITextSpellCheckingType(rawValue: value) {
            textField.spellCheckingType = spellCheckingType
        }
        if let value = item?.keyboardType,
           let keyboardType = UIKeyboardType(rawValue: value) {
            textField.keyboardType = keyboardType
        }
        if let value = item?.returnKeyType,
           let returnKeyType = UIReturnKeyType(rawValue: value) {
            textField.returnKeyType = returnKeyType
        }

        if let key = item?.key {
            observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(key), object: nil, queue: nil) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.textField.text = UserDefaults.standard.string(forKey: key)
                }
            })
        }
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
            UserDefaults.standard.set(textField.text, forKey: key)
            if let notification = item?.notification {
                source?.performAction(key: notification)
                NotificationCenter.default.post(name: NSNotification.Name(notification), object: nil)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

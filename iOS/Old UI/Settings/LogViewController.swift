//
//  LogViewController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 5/24/22.
//

import UIKit

class LogViewController: UIViewController {
    private let textView = UITextView()
    private var entries: [LogEntry] = []

    private var logTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("LOGS", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("CLEAR"),
            style: .plain,
            target: self,
            action: #selector(clearLog)
        )

        textView.attributedText = NSAttributedString(string: "Log is empty")
        textView.font = UIFont(name: "Menlo", size: 12)
        textView.textColor = .label
        textView.isEditable = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        textView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        textView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        textView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        textView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        logTask = Task {
            entries = await LogManager.logger.store.entries
            loadLog()
            let stream = await LogManager.logger.store.logStream()
            for await entry in stream {
                self.entries.append(entry)
                self.logEntry(entry: entry)
            }
        }
    }

    func loadLog() {
        textView.attributedText = NSMutableAttributedString()
        entries.forEach { logEntry(entry: $0) }
    }

    @MainActor
    func logEntry(entry: LogEntry) {
        if let string = textView.attributedText.mutableCopy() as? NSMutableAttributedString {
            switch entry.type {
                case .default:
                    break
                case .info:
                    string.append(NSAttributedString(string: "[INFO] ", attributes: [.foregroundColor: UIColor.systemBlue]))
                case .debug:
                    string.append(NSAttributedString(string: "[DEBUG] ", attributes: [.foregroundColor: UIColor.label]))
                case .warning:
                    string.append(NSAttributedString(string: "[WARN] ", attributes: [.foregroundColor: UIColor.systemYellow]))
                case .error:
                    string.append(NSAttributedString(string: "[ERROR] ", attributes: [.foregroundColor: UIColor.systemRed]))
            }
            string.append(NSAttributedString(string: entry.message + "\n", attributes: [.foregroundColor: UIColor.label]))
            string.addAttributes([.font: UIFont(name: "Menlo", size: 12) as Any], range: NSRange(location: 0, length: string.length))
            textView.attributedText = string
        }
    }

    @objc func clearLog() {
        entries = []
        textView.attributedText = NSMutableAttributedString()
        Task {
            await LogManager.logger.store.clear()
        }
    }
}

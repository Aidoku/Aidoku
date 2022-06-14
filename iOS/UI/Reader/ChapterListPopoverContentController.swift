//
//  ChapterListPopoverContentController.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/16/22.
//

import UIKit

protocol ChapterListPopoverDelegate: AnyObject {
    func chapterSelected(_ chapter: Chapter)
}

class ChapterListPopoverContentController: UIViewController {
    let chapterList: [Chapter]
    var selectedIndex: Int
    var hoveredIndexPath: IndexPath?
    var hovering = false

    weak var delegate: ChapterListPopoverDelegate?

    weak var tableView: UITableView?

    init(chapterList: [Chapter], selectedIndex: Int = 0) {
        self.chapterList = chapterList
        self.selectedIndex = selectedIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UITableView(frame: .zero, style: .plain)
        tableView = view as? UITableView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView?.dataSource = self
        tableView?.delegate = self

        tableView?.backgroundColor = .clear
        tableView?.separatorColor = .label.withAlphaComponent(0.2)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        becomeFirstResponder()

        tableView?.layoutIfNeeded()
        guard selectedIndex < chapterList.count else { return }
        tableView?.scrollToRow(at: IndexPath(row: selectedIndex, section: 0), at: .middle, animated: false)
    }
}

extension ChapterListPopoverContentController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chapterList.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UITableViewCell? = tableView.dequeueReusableCell(withIdentifier: "UITableViewCell")
        if cell == nil {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "UITableViewCell")
        }
        guard let cell = cell else { return UITableViewCell() }

        let chapter = chapterList[indexPath.row]
        let volume = chapter.volumeNum

        var chapterString = ""
        if let volume = volume, volume > 0 {
            chapterString.append(String(format: "\(NSLocalizedString("VOL_X", comment: "")) ", volume))
        }
        chapterString.append(String(format: NSLocalizedString("CH_X", comment: ""), chapter.chapterNum ?? 0))

        cell.backgroundColor = .clear
        cell.textLabel?.text = chapterString
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15)
        if let title: String = chapter.title {
            cell.detailTextLabel?.text = title
            cell.detailTextLabel?.font = cell.textLabel?.font
            cell.detailTextLabel?.textColor = .secondaryLabel
        } else {
            cell.detailTextLabel?.text = nil
        }
        if indexPath.row == selectedIndex {
            cell.accessoryType = .checkmark
        } else {
            cell.accessoryType = .none
        }

        return cell
    }
}

extension ChapterListPopoverContentController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selectedIndex != indexPath.row {
            let currentCell = tableView.cellForRow(at: IndexPath(row: selectedIndex, section: 0))
            currentCell?.accessoryType = .none

            delegate?.chapterSelected(chapterList[indexPath.row])
            selectedIndex = indexPath.row

            let selectedCell = tableView.cellForRow(at: indexPath)
            selectedCell?.accessoryType = .checkmark
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Key Handler
extension ChapterListPopoverContentController {
    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resignFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(
                title: "Select Previous Item in List",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputUpArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Select Next Item in List",
                action: #selector(arrowKeyPressed(_:)),
                input: UIKeyCommand.inputDownArrow,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Confirm Selection",
                action: #selector(enterKeyPressed),
                input: "\r",
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            ),
            UIKeyCommand(
                title: "Clear Selection",
                action: #selector(escKeyPressed),
                input: UIKeyCommand.inputEscape,
                modifierFlags: [],
                alternates: [],
                attributes: [],
                state: .off
            )
        ]
    }

    @objc func arrowKeyPressed(_ sender: UIKeyCommand) {
        guard let tableView = tableView else { return }
        if !hovering {
            hovering = true
            if hoveredIndexPath == nil { hoveredIndexPath = IndexPath(row: 0, section: 0) }
            tableView.cellForRow(at: hoveredIndexPath!)?.setHighlighted(true, animated: true)
            return
        }
        guard let hoveredIndexPath = hoveredIndexPath else { return }
        var position = hoveredIndexPath.row
        var section = hoveredIndexPath.section
        switch sender.input {
        case UIKeyCommand.inputUpArrow: position -= 1
        case UIKeyCommand.inputDownArrow: position += 1
        default: return
        }
        if position < 0 {
            guard section > 0 else { return }
            section -= 1
            position = tableView.numberOfRows(inSection: section) - 1
        } else if position >= tableView.numberOfRows(inSection: section) {
            guard section < tableView.numberOfSections - 1 else { return }
            section += 1
            position = 0
        }
        let newHoveredIndexPath = IndexPath(row: position, section: section)
        tableView.cellForRow(at: hoveredIndexPath)?.setHighlighted(false, animated: true)
        tableView.cellForRow(at: newHoveredIndexPath)?.setHighlighted(true, animated: true)
        tableView.scrollToRow(at: newHoveredIndexPath, at: .middle, animated: true)
        self.hoveredIndexPath = newHoveredIndexPath
    }

    @objc func enterKeyPressed() {
        guard let tableView = tableView else { return }
        guard !tableView.isEditing, hovering, let hoveredIndexPath = hoveredIndexPath else { return }
        self.tableView(tableView, didSelectRowAt: hoveredIndexPath)
    }

    @objc func escKeyPressed() {
        guard let tableView = tableView else { return }
        guard !tableView.isEditing, hovering, let hoveredIndexPath = hoveredIndexPath else { return }
        tableView.cellForRow(at: hoveredIndexPath)?.setHighlighted(false, animated: true)
        hovering = false
        self.hoveredIndexPath = nil
    }
}

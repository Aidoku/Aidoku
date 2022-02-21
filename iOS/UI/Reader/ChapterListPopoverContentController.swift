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
            chapterString.append(String(format: "Vol.%g ", volume))
        }
        chapterString.append(String(format: "Ch.%g", chapter.chapterNum ?? 0))

        cell.backgroundColor = .clear
        cell.textLabel?.text = chapterString
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15)
        if let title: String = chapter.title {
            cell.detailTextLabel?.text = title
            cell.detailTextLabel?.font = cell.textLabel?.font
            cell.detailTextLabel?.textColor = .secondaryLabel
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

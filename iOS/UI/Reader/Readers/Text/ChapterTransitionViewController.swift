//
//  ChapterTransitionViewController.swift
//  Aidoku
//

import AidokuRunner
import UIKit

class ChapterTransitionViewController: UIViewController {
    enum Direction {
        case next
        case previous
    }

    let direction: Direction
    let chapter: AidokuRunner.Chapter?
    weak var parentReader: ReaderPagedTextViewController?

    private var infoView: ReaderInfoPageView?

    init(
        direction: Direction,
        chapter: AidokuRunner.Chapter?,
        currentChapter: AidokuRunner.Chapter?,
        sourceId: String,
        mangaId: String,
        parentReader: ReaderPagedTextViewController?
    ) {
        self.direction = direction
        self.chapter = chapter
        self.parentReader = parentReader
        super.init(nibName: nil, bundle: nil)

        let infoPageType: ReaderInfoPageType = direction == .next ? .next : .previous
        let infoView = ReaderInfoPageView(type: infoPageType)

        // Set chapter info using the old Chapter model (matching the image reader)
        infoView.currentChapter = currentChapter?.toOld(sourceId: sourceId, mangaId: mangaId)
        if direction == .previous {
            infoView.previousChapter = chapter?.toOld(sourceId: sourceId, mangaId: mangaId)
        } else {
            infoView.nextChapter = chapter?.toOld(sourceId: sourceId, mangaId: mangaId)
        }

        self.infoView = infoView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        guard let infoView else { return }
        infoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoView)

        NSLayoutConstraint.activate([
            infoView.topAnchor.constraint(equalTo: view.topAnchor),
            infoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            infoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            infoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

}

// MARK: - Transition Action
extension ChapterTransitionViewController {
    /// Called when the user swipes past the transition page to confirm navigation.
    func performTransition() {
        guard chapter != nil else { return }
        if direction == .next {
            parentReader?.loadNextChapter()
        } else {
            parentReader?.loadPreviousChapter()
        }
    }
}

// MARK: - Chapter Load Trigger
/// Blank page placed beyond the transition info page.
/// When the user swipes onto this page, it triggers the actual chapter load.
class ChapterLoadTriggerViewController: UIViewController {
    let transitionVC: ChapterTransitionViewController

    init(transitionVC: ChapterTransitionViewController) {
        self.transitionVC = transitionVC
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }
}

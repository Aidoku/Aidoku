//
//  ReaderTransitionNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/22/23.
//

import AsyncDisplayKit

struct Transition {
    enum TransitionType {
        case next, prev
    }

    var type: TransitionType
    var from: Chapter
    var to: Chapter?
}

class ReaderTransitionNode: ASDisplayNode {

    var transition: Transition

    private static let defaultFontSize: CGFloat = 16
    private lazy var fontSize = Self.defaultFontSize
    private var lastWidth: CGFloat = 0

    func title(for chapter: Chapter) -> String {
        if let chapterTitle = chapter.title {
            return [
                String(format: NSLocalizedString("CH_X", comment: ""), chapter.chapterNum ?? 0),
                "-",
                chapterTitle
            ].joined(separator: " ")
        } else {
            return String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapter.chapterNum ?? 0)
        }
    }

    lazy var topChapterTextNode: ASTextNode = {
        let node = ASTextNode()
        node.attributedText = NSAttributedString(
            string: transition.type == .prev
                ? NSLocalizedString("PREVIOUS_COLON", comment: "")
                : NSLocalizedString("FINISHED_COLON", comment: ""),
            attributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize, weight: .medium)
            ]
        )
        return node
    }()

    lazy var topChapterTitleTextNode: ASTextNode = {
        let node = ASTextNode()
        guard
            let chapter = transition.type == .prev
                ? transition.to
                : transition.from
        else { return node }
        node.attributedText = NSAttributedString(
            string: title(for: chapter),
            attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
            ]
        )
        node.maximumNumberOfLines = 2
        return node
    }()

    lazy var bottomChapterTextNode: ASTextNode = {
        let node = ASTextNode()
        node.attributedText = NSAttributedString(
            string: transition.type == .prev
                ? NSLocalizedString("CURRENT_COLON", comment: "")
                : NSLocalizedString("NEXT_COLON", comment: ""),
            attributes: [
                .foregroundColor: UIColor.label,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize, weight: .medium)
            ]
        )
        return node
    }()

    lazy var bottomChapterTitleTextNode: ASTextNode = {
        let node = ASTextNode()
        guard
            let chapter = transition.type == .prev
                ? transition.from
                : transition.to
        else { return node }
        node.attributedText = NSAttributedString(
            string: title(for: chapter),
            attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
            ]
        )
        node.maximumNumberOfLines = 2
        return node
    }()

    lazy var noChapterTextNode: ASTextNode = {
        let node = ASTextNode()
        node.attributedText = NSAttributedString(
            string: transition.type == .prev
                ? NSLocalizedString("NO_PREVIOUS_CHAPTER", comment: "")
                : NSLocalizedString("NO_NEXT_CHAPTER", comment: ""),
            attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.systemFont(ofSize: Self.defaultFontSize)
            ]
        )
        return node
    }()

    init(transition: Transition) {
        self.transition = transition
        super.init()
        automaticallyManagesSubnodes = true
        backgroundColor = .systemBackground
    }

    override func layout() {
        super.layout()
        if frame.width != lastWidth {
            lastWidth = frame.width
            fontSize = Self.defaultFontSize - Self.defaultFontSize * (1 - frame.width / UIScreen.main.bounds.width) / 3
            func fixText(node: ASTextNode) {
                if let attr = node.attributedText?.mutableCopy() as? NSMutableAttributedString {
                    attr.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize), range: NSRange(0..<attr.length))
                    node.attributedText = attr
                }
            }
            fixText(node: topChapterTextNode)
            fixText(node: topChapterTitleTextNode)
            fixText(node: bottomChapterTextNode)
            fixText(node: bottomChapterTitleTextNode)
            fixText(node: noChapterTextNode)
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if transition.to == nil {
            return ASCenterLayoutSpec(
                horizontalPosition: .center,
                verticalPosition: .center,
                sizingOption: [],
                child: noChapterTextNode
            )
        } else {
            return ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: fontSize, left: fontSize * 2, bottom: fontSize, right: fontSize * 2),
                child: ASCenterLayoutSpec(
                    horizontalPosition: .center,
                    verticalPosition: .center,
                    sizingOption: .minimumWidth,
                    child: ASStackLayoutSpec(
                        direction: .vertical,
                        spacing: fontSize * 7/8,
                        justifyContent: .center,
                        alignItems: .start,
                        children: [
                            ASStackLayoutSpec(
                                direction: .vertical,
                                spacing: 2,
                                justifyContent: .center,
                                alignItems: .start,
                                children: [
                                    topChapterTextNode,
                                    topChapterTitleTextNode
                                ]
                            ),
                            ASStackLayoutSpec(
                                direction: .vertical,
                                spacing: 2,
                                justifyContent: .center,
                                alignItems: .start,
                                children: [
                                    bottomChapterTextNode,
                                    bottomChapterTitleTextNode
                                ]
                            )
                        ]
                    )
                )
            )
        }
    }
}

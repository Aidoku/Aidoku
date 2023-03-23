//
//  ReaderWebtoonTransitionNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/22/23.
//

import AsyncDisplayKit

class ReaderWebtoonTransitionNode: ASCellNode {

    let transition: Transition

    init(transition: Transition) {
        self.transition = transition
        super.init()
        automaticallyManagesSubnodes = true
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        ASRatioLayoutSpec(ratio: 1, child: ReaderTransitionNode(transition: transition))
    }
}

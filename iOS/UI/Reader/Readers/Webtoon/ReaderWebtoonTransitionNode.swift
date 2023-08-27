//
//  ReaderWebtoonTransitionNode.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 3/22/23.
//

import AsyncDisplayKit

class ReaderWebtoonTransitionNode: BaseObservingCellNode {

    let transition: Transition

    var pillarbox = UserDefaults.standard.bool(forKey: "Reader.pillarbox")
    var pillarboxAmount: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "Reader.pillarboxAmount"))
    var pillarboxOrientation = UserDefaults.standard.string(forKey: "Reader.pillarboxOrientation")

    lazy var transitionNode = ReaderTransitionNode(transition: transition)

    init(transition: Transition) {
        self.transition = transition
        super.init()
        automaticallyManagesSubnodes = true
        addObserver(forName: "Reader.pillarbox") { [weak self] notification in
            self?.pillarbox = notification.object as? Bool ?? false
        }
        addObserver(forName: "Reader.pillarboxAmount") { [weak self] notification in
            guard let doubleValue = notification.object as? Double else { return }
            self?.pillarboxAmount = CGFloat(doubleValue)
        }
        addObserver(forName: "Reader.pillarboxOrientation") { [weak self] notification in
            self?.pillarboxOrientation = notification.object as? String ?? "both"
        }
    }

    func isPillarboxOrientation() -> Bool {
        pillarboxOrientation == "both" ||
            (pillarboxOrientation == "portrait" && UIDevice.current.orientation.isPortrait) ||
            (pillarboxOrientation == "landscape" && UIDevice.current.orientation.isLandscape)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if pillarbox && isPillarboxOrientation() {
            let percent = (100 - pillarboxAmount) / 100
            let height = constrainedSize.max.width * percent

            transitionNode.style.width = ASDimensionMakeWithFraction(percent)
            transitionNode.style.height = ASDimensionMakeWithPoints(height)
            transitionNode.style.alignSelf = .center

            return ASCenterLayoutSpec(
                horizontalPosition: .center,
                verticalPosition: .center,
                sizingOption: [],
                child: transitionNode
            )
        } else {
            return ASRatioLayoutSpec(ratio: 1, child: transitionNode)
        }
    }
}

//
//  ClearStaleListSelection.swift
//  Aidoku
//
//  Created by Amqx on 8/6/26.
//

import SwiftUI
import SwiftUIIntrospect

// Use to fix off-screen rows retaining stale selection checkmarks on Lists.
private struct ClearStaleListSelectionModifier<Value: Hashable>: ViewModifier {
    let selection: Set<Value>

    @State private var box = CollectionViewBox()

    @Environment(\.listSelectionRestoreState) private var restoreState

    func body(content: Content) -> some View {
        content
            .introspect(.list, on: .iOS(.v16, .v17, .v18, .v26, .v27)) { collectionView in
                box.collectionView = collectionView
            }
            .onChangeWrapper(of: selection) { _, selection in
                // ignore the empty state a selection restore passes through
                guard restoreState?.isRestoring != true else { return }
                guard selection.isEmpty, let collectionView = box.collectionView else { return }
                for indexPath in collectionView.indexPathsForSelectedItems ?? [] {
                    collectionView.deselectItem(at: indexPath, animated: false)
                }
            }
    }
}

private class CollectionViewBox {
    weak var collectionView: UICollectionView?
}

extension View {
    func clearsStaleListSelection<Value: Hashable>(_ selection: Set<Value>) -> some View {
        modifier(ClearStaleListSelectionModifier(selection: selection))
    }
}

//
//  RestoreListSelectionOnAppear.swift
//  Aidoku
//
//  Created by Amqx on 8/6/26.
//

import SwiftUI

// Remove then re-add an entry to force a re-render.
// Apply this outside of clearsStaleListSelection, so the transient selection change is ignored there.
private struct RestoreListSelectionOnAppearModifier<Value: Hashable>: ViewModifier {
    @Binding var selection: Set<Value>

    @State private var appeared = false
    @State private var restoreState = ListSelectionRestoreState()

    func body(content: Content) -> some View {
        content
            .environment(\.listSelectionRestoreState, restoreState)
            .onAppear {
                // the first appearance renders from scratch, so there's nothing to restore
                guard appeared else {
                    appeared = true
                    return
                }
                guard let value = selection.first else { return }
                // with a single entry selected the selection is briefly empty, which would otherwise
                // look like a deselection and wipe the selection in the backing collection view
                restoreState.isRestoring = true
                selection.remove(value)
                DispatchQueue.main.async {
                    selection.insert(value)
                    restoreState.isRestoring = false
                }
            }
    }
}

// Marks a selection round-trip in progress, so other selection modifiers can ignore it.
class ListSelectionRestoreState {
    var isRestoring = false
}

private struct ListSelectionRestoreStateKey: EnvironmentKey {
    static let defaultValue: ListSelectionRestoreState? = nil
}

extension EnvironmentValues {
    var listSelectionRestoreState: ListSelectionRestoreState? {
        get { self[ListSelectionRestoreStateKey.self] }
        set { self[ListSelectionRestoreStateKey.self] = newValue }
    }
}

extension View {
    func restoresListSelectionOnAppear<Value: Hashable>(_ selection: Binding<Set<Value>>) -> some View {
        modifier(RestoreListSelectionOnAppearModifier(selection: selection))
    }
}

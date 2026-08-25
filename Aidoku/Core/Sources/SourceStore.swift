//
//  SourceStore.swift
//  Aidoku
//
//  Created by skitty on 8/25/26.
//

import AidokuRunner
import Foundation

@MainActor
final class SourceStore: ObservableObject {
    @Published private(set) var sourcesByKey: [String: AidokuRunner.Source] = [:]
    @Published private(set) var disabledSourceKeys: Set<String> = []

    func update(
        sourcesByKey: [String: AidokuRunner.Source],
        disabledSourceKeys: Set<String>
    ) {
        self.sourcesByKey = sourcesByKey
        self.disabledSourceKeys = disabledSourceKeys
    }

    func source(for key: String) -> AidokuRunner.Source? {
        sourcesByKey[key]
    }

    func isInstalled(sourceKey: String) -> Bool {
        sourcesByKey[sourceKey] != nil
    }

    func isDisabled(sourceKey: String) -> Bool {
        disabledSourceKeys.contains(sourceKey)
    }

    var localSourceInstalled: Bool {
        sourcesByKey[LocalSourceRunner.sourceKey] != nil
    }
}

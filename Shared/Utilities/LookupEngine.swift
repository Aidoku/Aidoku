//
//  LookupEngine.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Based on: https://github.com/Manhhao/Hoshi-Reader/blob/ff31274acf44683e5b61abdfb2a273fc738d4711/Core/LookupEngine.swift
//  Modified for use in Aidoku
//

import Foundation
import CHoshiDicts

@available(iOS 18.0, macOS 15.0, *)
class LookupEngine {
    static let shared = LookupEngine()

    private nonisolated final class Bundle: @unchecked Sendable {
        var dictQuery = DictionaryQuery()
        var deinflector = Deinflector()
        var lookup: Lookup!

        init(termPaths: [URL], freqPaths: [URL], pitchPaths: [URL]) {
            for path in termPaths {
                dictQuery.add_term_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in freqPaths {
                dictQuery.add_freq_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in pitchPaths {
                dictQuery.add_pitch_dict(std.string(path.path(percentEncoded: false)))
            }
            lookup = Lookup(&dictQuery, &deinflector)
        }
    }

    private var bundle: Bundle?
    private var generation = 0

    var isReady: Bool {
        bundle != nil
    }

    private init() {}

    func buildQuery(termPaths: [URL], freqPaths: [URL], pitchPaths: [URL]) {
        generation += 1
        let token = generation
        Task.detached(priority: .userInitiated) {
            let newBundle = Bundle(termPaths: termPaths, freqPaths: freqPaths, pitchPaths: pitchPaths)
            await MainActor.run {
                guard token == self.generation else { return }
                self.bundle = newBundle
            }
        }
    }

    func lookup(_ str: String, maxResults: Int = 16, scanLength: Int = 16) -> [LookupResult] {
        guard let bundle else { return [] }
        return Array(bundle.lookup.lookup(std.string(str), Int32(maxResults), scanLength))
    }

    func getStyles() -> [DictionaryStyle] {
        guard let bundle else { return [] }
        return Array(bundle.dictQuery.get_styles())
    }

    func withMediaFile<T>(dictName: String, mediaPath: String, _ body: (Data) -> T) -> T {
        guard let bundle else { return body(Data()) }
        let view = bundle.dictQuery.get_media_file_view(std.string(dictName), std.string(mediaPath))
        let size = Int(view.size)
        guard size > 0, let ptr = UnsafeMutableRawPointer(mutating: view.data) else {
            return body(Data())
        }
        let data = Data(bytesNoCopy: ptr, count: size, deallocator: .none)
        return body(data)
    }

    func getMediaFile(dictName: String, mediaPath: String) -> Data {
        withMediaFile(dictName: dictName, mediaPath: mediaPath) { Data($0) }
    }
}

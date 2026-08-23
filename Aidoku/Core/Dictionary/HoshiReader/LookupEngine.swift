//
//  LookupEngine.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//
//  Based on: https://github.com/Manhhao/Hoshi-Reader/blob/c31c9d0ce376ff83bf6a91d908bf9f8e0fb4947b/Core/LookupEngine.swift
//  Modified for use in Aidoku
//

import Foundation
import CHoshiDicts
import CxxStdlib

@available(iOS 18.0, macOS 15.0, *)
class LookupEngine {
    static let shared = LookupEngine()

    private nonisolated final class Bundle: @unchecked Sendable {
        var dictQuery = DictionaryQuery()
        var deinflector = Deinflector()
        var lookup: Lookup!

        init(termPaths: [URL], freqPaths: [URL], pitchPaths: [URL], kanjiPaths: [URL]) {
            for path in termPaths {
                dictQuery.add_term_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in freqPaths {
                dictQuery.add_freq_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in pitchPaths {
                dictQuery.add_pitch_dict(std.string(path.path(percentEncoded: false)))
            }
            for path in kanjiPaths {
                dictQuery.add_kanji_dict(std.string(path.path(percentEncoded: false)))
            }
            lookup = Lookup(&dictQuery, &deinflector)
        }
    }

    private var bundle: Bundle?
    private var generation = 0
    private var buildTask: Task<Void, Never>?

    var isReady: Bool {
        bundle != nil
    }

    private init() {}

    func buildQuery(termPaths: [URL], freqPaths: [URL], pitchPaths: [URL], kanjiPaths: [URL]) {
        generation += 1
        let token = generation
        let previous = buildTask
        buildTask = Task.detached(priority: .userInitiated) {
            await previous?.value
            guard await MainActor.run(body: { token == self.generation }) else { return }
            let newBundle = Bundle(termPaths: termPaths, freqPaths: freqPaths, pitchPaths: pitchPaths, kanjiPaths: kanjiPaths)
            await MainActor.run {
                guard token == self.generation else { return }
                self.bundle = newBundle
            }
        }
    }

    func lookup(_ str: String, maxResults: Int = 16, scanLength: Int = 16) -> [LookupResult] {
        guard let bundle else { return [] }
        return Array(bundle.lookup.lookup(std.string(str), Int32(maxResults), scanLength, LookupOptions()))
    }

    func queryKanji(_ kanji: String) -> [String: Any]? {
        guard let bundle else { return nil }
        let result = bundle.dictQuery.query_kanji(std.string(kanji))
        var entries: [[String: Any]] = []
        for entry in result.entries {
            var meanings: [String] = []
            for definition in entry.definitions {
                meanings.append(String(definition))
            }
            entries.append([
                "dictName": String(entry.dict_name),
                "onyomi": String(entry.onyomi),
                "kunyomi": String(entry.kunyomi),
                "meanings": meanings
            ])
        }
        guard !entries.isEmpty else { return nil }
        return [
            "character": String(result.character),
            "entries": entries
        ]
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

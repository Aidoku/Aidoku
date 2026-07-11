//
//  LookupEngine.swift
//  Aidoku
//
//  Created with reference to Hoshi Reader by Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CHoshiDicts

@available(iOS 18.0, macOS 15.0, *)
class LookupEngine {
    static let shared = LookupEngine()

    private var dictQuery: DictionaryQuery?
    private var deinflector: Deinflector?
    private var lookupEngine: Lookup?

    private init() {
        deinflector = Deinflector()
    }

    func buildQuery(termPaths: [URL], freqPaths: [URL], pitchPaths: [URL]) {
        lookupEngine = nil
        dictQuery = nil

        guard !termPaths.isEmpty else {
            return
        }

        dictQuery = DictionaryQuery()
        for path in termPaths {
            dictQuery?.add_term_dict(std.string(path.path(percentEncoded: false)))
        }
        for path in freqPaths {
            dictQuery?.add_freq_dict(std.string(path.path(percentEncoded: false)))
        }
        for path in pitchPaths {
            dictQuery?.add_pitch_dict(std.string(path.path(percentEncoded: false)))
        }
        if dictQuery != nil, deinflector != nil {
            lookupEngine = Lookup(&dictQuery!, &deinflector!)
        }
    }

    var isReady: Bool {
        lookupEngine != nil
    }

    func lookup(_ str: String, maxResults: Int = 16) -> [DictEntryData] {
        guard let lookupEngine else { return [] }
        let results = Array(lookupEngine.lookup(std.string(str), Int32(maxResults)))
        return results.map { result in
            let expression = String(result.term.expression)
            let reading = String(result.term.reading)
            let matched = String(result.matched)
            let deinflectionTrace = result.trace.map {
                DictDeinflectionTag(name: String($0.name), description: String($0.description))
            }

            var glossaries: [DictGlossaryData] = []
            for glossary in result.term.glossaries {
                glossaries.append(DictGlossaryData(
                    dictionary: String(glossary.dict_name),
                    content: String(glossary.glossary),
                    definitionTags: String(glossary.definition_tags),
                    termTags: String(glossary.term_tags)
                ))
            }

            var frequencies: [DictFrequencyData] = []
            for frequency in result.term.frequencies {
                var tags: [DictFrequencyTag] = []
                for tag in frequency.frequencies {
                    tags.append(DictFrequencyTag(
                        value: Int(tag.value),
                        displayValue: String(tag.display_value)
                    ))
                }
                frequencies.append(DictFrequencyData(
                    dictionary: String(frequency.dict_name),
                    frequencies: tags
                ))
            }

            var pitches: [DictPitchData] = []
            for pitchEntry in result.term.pitches {
                var positions: [Int] = []
                for element in pitchEntry.pitch_positions {
                    let pos = Int(element)
                    if !positions.contains(pos) {
                        positions.append(pos)
                    }
                }
                pitches.append(DictPitchData(
                    dictionary: String(pitchEntry.dict_name),
                    pitchPositions: positions
                ))
            }

            return DictEntryData(
                expression: expression,
                reading: reading,
                matched: matched,
                deinflectionTrace: deinflectionTrace,
                glossaries: glossaries,
                frequencies: frequencies,
                pitches: pitches,
                definitionTags: []
            )
        }
    }

    func getStyles() -> [String: String] {
        guard dictQuery != nil else { return [:] }
        var styles: [String: String] = [:]
        for style in dictQuery!.get_styles() {
            let name = String(style.dict_name)
            let css = String(style.styles)
            if !css.isEmpty {
                styles[name] = css
            }
        }
        return styles
    }
}

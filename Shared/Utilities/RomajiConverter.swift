//
//  RomajiConverter.swift
//  Aidoku
//
//  Created by skitty on 7/25/26.
//

enum RomajiConverter {
    private static let kana: [String: String] = [
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "sa": "さ", "shi": "し", "si": "し", "su": "す", "se": "せ", "so": "そ",
        "ta": "た", "chi": "ち", "ti": "ち", "tsu": "つ", "tu": "つ", "te": "て", "to": "と",
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ",
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "ya": "や", "yu": "ゆ", "yo": "よ",
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "wa": "わ", "wo": "を",
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "za": "ざ", "ji": "じ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ",
        "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "sya": "しゃ", "syu": "しゅ", "syo": "しょ",
        "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "tya": "ちゃ", "tyu": "ちゅ", "tyo": "ちょ",
        "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ",
        "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ",
        "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
        "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ",
        "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ",
        "ja": "じゃ", "ju": "じゅ", "jo": "じょ", "jya": "じゃ", "jyu": "じゅ", "jyo": "じょ",
        "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
        "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ"
    ]

    // convert romaji text to possible hiragana text (e.g. yonya -> [よんや, よにゃ])
    static func hiraganaCandidates(for text: String) -> Set<String>? {
        let input = text.lowercased().filter { !$0.isWhitespace && $0 != "-" }
        guard !input.isEmpty, input.allSatisfy({ $0.isLetter || $0 == "'" }) else { return nil }

        var results = Set<String>()
        var stack: [(index: String.Index, current: String)] = [(input.startIndex, "")]

        while let state = stack.popLast(), results.count < 32 {
            guard state.index < input.endIndex else {
                results.insert(state.current)
                continue
            }

            let char = input[state.index]
            let nextIndex = input.index(after: state.index)
            if nextIndex < input.endIndex, char == input[nextIndex], isDoubleConsonant(char) {
                stack.append((nextIndex, state.current + "っ"))
            }

            if char == "n" {
                if nextIndex == input.endIndex {
                    stack.append((nextIndex, state.current + "ん"))
                } else if input[nextIndex] == "'" {
                    stack.append((input.index(after: nextIndex), state.current + "ん"))
                } else if !isVowel(input[nextIndex]) || input[nextIndex] == "y" {
                    stack.append((nextIndex, state.current + "ん"))
                }
            }

            for length in [3, 2, 1] {
                guard let endIndex = input.index(state.index, offsetBy: length, limitedBy: input.endIndex) else { continue }
                let key = String(input[state.index..<endIndex])
                if let value = kana[key] {
                    stack.append((endIndex, state.current + value))
                }
            }
        }

        return results.isEmpty ? nil : results
    }

    private static func isVowel(_ character: Character) -> Bool {
        character == "a" || character == "i" || character == "u" || character == "e" || character == "o"
    }

    private static func isDoubleConsonant(_ character: Character) -> Bool {
        !isVowel(character) && character != "n" && character != "'"
    }
}

//
//  LocalFileNameParser.swift
//  Aidoku
//
//  Created by Skitty on 11/13/25.
//

import Foundation

// https://github.com/Kareadita/Kavita/blob/develop/API/Services/Tasks/Scanner/Parser/Parser.cs#L777
enum LocalFileNameParser {
    static func parseMangaSeries(from filename: String) -> String {
        let (series, _) = firstMatchGroup(mangaSeriesPatterns, in: filename, groupName: "Series")
        if let series {
            return cleanTitle(series)
        }
        return ""
    }

    static func parseMangaVolume(from filename: String) -> String {
        let cleaned = removeDuplicateVolumeIfExists(filename)
        let (volume, hasPart) = firstMatchGroup(mangaVolumePatterns, in: cleaned, groupName: "Volume")
        if let volume {
            return formatValue(volume, hasPart: hasPart)
        }
        return ""
    }

    static func parseMangaChapter(from filename: String) -> String {
        let cleaned = removeDuplicateChapterIfExists(filename)
        let (chapter, hasPart) = firstMatchGroup(mangaChapterPatterns, in: cleaned, groupName: "Chapter")
        if let chapter {
            return formatValue(chapter, hasPart: hasPart)
        }
        return ""
    }

    static func getMangaVolumeNumber(from filename: String) -> Float? {
        let string = parseMangaVolume(from: filename)
        guard !string.isEmpty else { return nil }
        if let rangeIndex = string.firstIndex(of: "-") {
            return Float(String(string[..<rangeIndex]))
        }
        return Float(string)
    }

    static func getMangaChapterNumber(from filename: String) -> Float? {
        let string = parseMangaChapter(from: filename)
        guard !string.isEmpty else { return nil }
        if let rangeIndex = string.firstIndex(of: "-") {
            return Float(String(string[..<rangeIndex]))
        }
        return Float(string)
    }
}

// MARK: - Regex Patterns
extension LocalFileNameParser {
    private static let mangaSeriesPatterns: [String] = [
        // Thai Volume: เล่ม n -> Volume n
        #"(?<Series>.+?)(เล่ม|เล่มที่)(\s)?(\.?)(\s|_)?(?<Volume>\d+(\-\d+)?(\.\d+)?)"#,
        // Russian Volume: Том n -> Volume n, Тома n -> Volume
        #"(?<Series>.+?)Том(а?)(\.?)(\s|_)?(?<Volume>\d+(?:(\-)\d+)?)"#,
        // Russian Volume: n Том -> Volume n
        #"(?<Series>.+?)(\s|_)?(?<Volume>\d+(?:(\-)\d+)?)(\s|_)Том(а?)"#,
        // Russian Chapter: n Главa -> Chapter n
        #"(?<Series>.+?)(?!Том)(?<!Том\.)\s\d+(\s|_)?(?<Chapter>\d+(?:\.\d+|-\d+)?)(\s|_)(Глава|глава|Главы|Глава)"#,
        // Russian Chapter: Главы n -> Chapter n
        #"(?<Series>.+?)(Глава|глава|Главы|Глава)(\.?)(\s|_)?(?<Chapter>\d+(?:.\d+|-\d+)?)"#,
        // Grand Blue Dreaming - SP02
        #"(?<Series>.*)(\b|_|-|\s)(?:sp)\d"#,
        // Mad Chimera World - Volume 005 - Chapter 026.cbz (couldn't figure out how to get Volume negative lookaround working on below regex),
        // The Duke of Death and His Black Maid - Vol. 04 Ch. 054.5 - V4 Omake
        #"(?<Series>.+?)(\s|_|-)+(?:Vol(ume|\.)?(\s|_|-)+\d+)(\s|_|-)+(?:(Ch|Chapter|Ch)\.?)(\s|_|-)+(?<Chapter>\d+)"#,
        // [SugoiSugoi]_NEEDLESS_Vol.2_-_Disk_The_Informant_5_[ENG].rar, Yuusha Ga Shinda! - Vol.tbd Chapter 27.001 V2 Infection ①.cbz,
        // Nagasarete Airantou - Vol. 30 Ch. 187.5 - Vol.30 Omake
        #"^(?<Series>.+?)(?:\s*|_|\-\s*)+(?:Ch(?:apter|\.|)\s*\d+(?:\.\d+)?(?:\s*|_|\-\s*)+)?Vol(?:ume|\.|)\s*(?:\d+|tbd)(?:\s|_|\-\s*).+"#,
        // Ichiban_Ushiro_no_Daimaou_v04_ch34_[VISCANS].zip, VanDread-v01-c01.zip
        #"(?<Series>.*)(\b|_)v(?<Volume>\d+-?\d*)(\s|_|-)"#,
        // Gokukoku no Brynhildr - c001-008 (v01) [TrinityBAKumA], Black Bullet - v4 c17 [batoto]
        #"(?<Series>.+?)( - )(?:v|vo|c|chapters|tome|t|ch)\d"#,
        // Kedouin Makoto - Corpse Party Musume, Chapter 19 [Dametrans].zip
        #"(?<Series>.*)(?:, Chapter )(?<Chapter>\d+)"#,
        // Please Go Home, Akutsu-San! - Chapter 038.5 - Volume Announcement.cbz, My Charms Are Wasted on Kuroiwa Medaka - Ch. 37.5 - Volume Extras
        #"(?<Series>.+?)(\s|_|-)(?!Vol)(\s|_|-)((?:Chapter)|(?:Ch\.))(\s|_|-)(?<Chapter>\d+)"#,
        // [dmntsf.net] One Piece - Digital Colored Comics Vol. 20 Ch. 177 - 30 Million vs 81 Million.cbz
        #"(?<Series>.+?):? (\b|_|-)(vol|tome)\.?(\s|-|_)?\d+"#,
        // [xPearse] Kyochuu Rettou Chapter 001 Volume 1 [English] [Manga] [Volume Scans]
        #"(?<Series>.+?):?(\s|\b|_|-)Chapter(\s|\b|_|-)\d+(\s|\b|_|-)(vol)(ume)"#,
        // Kyochuu Rettou T3, Kyochuu Rettou - Tome 3
        #"(?<Series>.+?):? (\b|_|-)(t\d+|tome(\b|_)\d+)"#,
        // [xPearse] Kyochuu Rettou Volume 1 [English] [Manga] [Volume Scans]
        #"(?<Series>.+?):? (\b|_|-)(vol)(ume)"#,
        // Knights of Sidonia c000 (S2 LE BD Omake - BLAME!) [Habanero Scans]
        #"(?<Series>.*?)(?<!\()\bc\d+\b"#,
        // Tonikaku Cawaii [Volume 11], Darling in the FranXX - Volume 01.cbz
        #"(?<Series>.*)(?: _|-|\[|\()\s?(vol(ume)?|tome|t\d+)"#,
        // Momo The Blood Taker - Chapter 027 Violent Emotion.cbz, Grand Blue Dreaming - SP02 Extra (2019) (Digital) (danke-Empire).cbz
        #"^(?<Series>(?!Vol).+?)(?:(ch(apter|\.)(\b|_|-|\s))|sp)\d"#,
        // Historys Strongest Disciple Kenichi_v11_c90-98.zip, Killing Bites Vol. 0001 Ch. 0001 - Galactica Scanlations (gb)
        #"(?<Series>.*) (\b|_|-)(v|ch\.?|c|s)\d+"#,
        // Hinowa ga CRUSH! 018 (2019) (Digital) (LuCaZ).cbz
        #"(?<Series>.*)\s+(?<Chapter>\d+)\s+(?:\(\d{4}\))\s"#,
        // Goblin Slayer - Brand New Day 006.5 (2019) (Digital) (danke-Empire)
        #"(?<Series>.*) (-)?(?<Chapter>\d+(?:.\d+|-\d+)?) \(\d{4}\)"#,
        // Noblesse - Episode 429 (74 Pages).7z
        #"(?<Series>.*)(\s|_)(?:Episode|Ep\.?)(\s|_)(?<Chapter>\d+(?:.\d+|-\d+)?)"#,
        // Akame ga KILL! ZERO (2016-2019) (Digital) (LuCaZ)
        #"(?<Series>.*)\(\d"#,
        // Tonikaku Kawaii (Ch 59-67) (Ongoing)
        #"(?<Series>.*)(\s|_)\((c\s|ch\s|chapter\s)"#,
        // Fullmetal Alchemist chapters 101-108
        #"(?<Series>.+?)(\s|_|\-)+?chapters(\s|_|\-)+?\d+(\s|_|\-)+?"#,
        // It's Witching Time! 001 (Digital) (Anonymous1234)
        #"(?<Series>.+?)(\s|_|\-)+?\d+(\s|_|\-)\("#,
        // Ichinensei_ni_Nacchattara_v01_ch01_[Taruby]_v1.1.zip must be before [Suihei Kiki]_Kasumi_Otoko_no_Ko_[Taruby]_v1.1.zip
        // due to duplicate version identifiers in file.
        #"(?<Series>.*)(v|s)\d+(-\d+)?(_|\s)"#,
        // [Suihei Kiki]_Kasumi_Otoko_no_Ko_[Taruby]_v1.1.zip
        #"(?<Series>.*)(v|s)\d+(-\d+)?"#,
        // Black Bullet (This is very loose, keep towards bottom)
        #"(?<Series>.*)(_)(v|vo|c|volume)( |_)\d+"#,
        // [Hidoi]_Amaenaideyo_MS_vol01_chp02.rar
        #"(?<Series>.*)( |_)(vol\d+)?( |_)(?:Chp\.? ?\d+)"#,
        // Mahoutsukai to Deshi no Futekisetsu na Kankei Chp. 1
        #"(?<Series>.*)( |_)(?:Chp.? ?\d+)"#,
        // Corpse Party -The Anthology- Sachikos game of love Hysteric Birthday 2U Chapter 01
        #"^(?!Vol)(?<Series>.*)( |_)Chapter( |_)(\d+)"#,

        // Fullmetal Alchemist chapters 101-108.cbz
        #"^(?!vol)(?<Series>.*)( |_)(chapters( |_)?)\d+-?\d*"#,
        // Umineko no Naku Koro ni - Episode 1 - Legend of the Golden Witch #1
        #"^(?!Vol\.?)(?<Series>.*)( |_|-)(?<!-)(episode|chapter|(ch\.?) ?)\d+-?\d*"#,
        // Baketeriya ch01-05.zip
        #"^(?!Vol)(?<Series>.*)ch\d+-?\d?"#,
        // Magi - Ch.252-005.cbz
        #"(?<Series>.*)( ?- ?)Ch\.\d+-?\d*"#,
        // Korean catch all for symbols 죠시라쿠! 2년 후 1권
        #"^(?!Vol)(?!Chapter)(?<Series>.+?)(-|_|\s|#)\d+(-\d+)?(권|화|話)"#,
        // [BAA]_Darker_than_Black_Omake-1, Bleach 001-002, Kodoja #001 (March 2016)
        #"^(?!Vol)(?!Chapter)(?<Series>.+?)(-|_|\s|#)\d+(-\d+)?"#,
        // Baketeriya ch01-05.zip, Akiiro Bousou Biyori - 01.jpg, Beelzebub_172_RHS.zip, Cynthia the Mission 29.rar, A Compendium of Ghosts - 031 - The Third Story_ Part 12 (Digital) (Cobalt001)
        #"^(?!Vol\.?)(?!Chapter)(?<Series>.+?)(\s|_|-)(?<!-)(ch|chapter)?\.?\d+-?\d*"#,
        // [BAA]_Darker_than_Black_c1 (This is very greedy, make sure it's close to last)
        #"^(?!Vol)(?<Series>.*)( |_|-)(ch?)\d+"#,
        // Japanese Volume: n巻 -> Volume n
        #"(?<Series>.+?)第(?<Volume>\d+(?:(\-)\d+)?)巻"#
    ]

    private static let mangaVolumePatterns: [String] = [
        // Thai Volume: เล่ม n -> Volume n
        #"(เล่ม|เล่มที่)(\s)?(\.?)(\s|_)?(?<Volume>\d+(\-\d+)?(\.\d+)?)"#,
        // Dance in the Vampire Bund v16-17, Dance in the Vampire Bund Tome 1
        #"(?<Series>.*)(\b|_)(v|tome(\s|_)?|t)(?<Volume>\d+-?\d+)(\s|_)"#,
        // Nagasarete Airantou - Vol. 30 Ch. 187.5 - Vol.31 Omake
        #"^(?<Series>.+?)(\s*Chapter\s*\d+)?(\s|_|\-\s)+((Vol(ume)?|tome)\.?(\s|_)?)(?<Volume>\d+(\.\d+)?)(.+?|$)"#,
        // Historys Strongest Disciple Kenichi_v11_c90-98.zip or Dance in the Vampire Bund v16-17
        #"(?<Series>.*)(\b|_)(?!\[)v(?<Volume>\d+(\.\d)?(-\d+(\.\d)?)?)(?!\])(\b|_)"#,
        // Kodomo no Jikan vol. 10, [dmntsf.net] One Piece - Digital Colored Comics Vol. 20.5-21.5 Ch. 177
        #"(?<Series>.*)(\b|_)(vol\.? ?)(?<Volume>\d+(\.\d)?(-\d+)?(\.\d)?)"#,
        // Killing Bites Vol. 0001 Ch. 0001 - Galactica Scanlations (gb)
        #"(vol\.? ?)(?<Volume>\d+(\.\d)?)"#,
        // Tonikaku Cawaii [Volume 11].cbz
        #"((volume|tome)\s)(?<Volume>\d+(\.\d)?)"#,
        // Tower Of God S01 014 (CBT) (digital).cbz, Tower Of God T01 014 (CBT) (digital).cbz,
        #"(?<Series>.*)(\b|_)((S|T)(?<Volume>\d+)(\b|_))"#,
        // vol_001-1.cbz for MangaPy default naming convention
        #"(vol_)(?<Volume>\d+(\.\d)?)"#,
        // Chinese Volume: 第n卷 -> Volume n, 第n册 -> Volume n, 幽游白书完全版 第03卷 天下 or 阿衰online 第1册
        #"第(?<Volume>\d+)(卷|册)"#,
        // Chinese Volume: 卷n -> Volume n, 册n -> Volume n
        #"(卷|册)(?<Volume>\d+)"#,
        // Korean Volume: 제n화|회|장 -> Volume n, n화|권|장 -> Volume n, 63권#200.zip -> Volume 63 (no chapter, #200 is just files inside)
        #"제?(?<Volume>\d+(\.\d+)?)(권|화|장)"#,
        // Korean Season: 시즌n -> Season n,
        #"시즌(?<Volume>\d+(\-\d+)?)"#,
        // Korean Season: 시즌n -> Season n, n시즌 -> season n
        #"(?<Volume>\d+(\-|~)?\d+?)시즌"#,
        // Korean Season: 시즌n -> Season n, n시즌 -> season n
        #"시즌(?<Volume>\d+(\-|~)?\d+?)"#,
        // Japanese Volume: n巻 -> Volume n
        #"(?<Volume>\d+(?:(\-)\d+)?)巻"#,
        // Russian Volume: Том n -> Volume n, Тома n -> Volume
        #"Том(а?)(\.?)(\s|_)?(?<Volume>\d+(?:(\-)\d+)?)"#,
        // Russian Volume: n Том -> Volume n
        #"(\s|_)?(?<Volume>\d+(?:(\-)\d+)?)(\s|_)Том(а?)"#
    ]

    private static let mangaChapterPatterns: [String] = [
        // Thai Chapter: บทที่ n -> Chapter n, ตอนที่ n -> Chapter n, เล่ม n -> Volume n, เล่มที่ n -> Volume n
        #"(?<Volume>((เล่ม|เล่มที่))?(\s|_)?\.?\d+)(\s|_)(บทที่|ตอนที่)\.?(\s|_)?(?<Chapter>\d+)"#,
        // Historys Strongest Disciple Kenichi_v11_c90-98.zip, ...c90.5-100.5
        #"(\b|_)(c|ch)(\.?\s?)(?<Chapter>(\d+(\.\d)?)(-c?\d+(\.\d)?)?)"#,
        // [Suihei Kiki]_Kasumi_Otoko_no_Ko_[Taruby]_v1.1.zip
        #"v\d+\.(\s|_)(?<Chapter>\d+(?:.\d+|-\d+)?)"#,
        // Umineko no Naku Koro ni - Episode 3 - Banquet of the Golden Witch #02.cbz (Rare case, if causes issue remove)
        #"^(?<Series>.*)(?: |_)#(?<Chapter>\d+)"#,
        // Green Worldz - Chapter 027, Kimi no Koto ga Daidaidaidaidaisuki na 100-nin no Kanojo Chapter 11-10
        #"^(?!Vol)(?<Series>.*)\s?(?<!vol\. )\sChapter\s(?<Chapter>\d+(?:\.?[\d-]+)?)"#,
        // Russian Chapter: Главы n -> Chapter n
        #"(Глава|глава|Главы|Глава)(\.?)(\s|_)?(?<Chapter>\d+(?:.\d+|-\d+)?)"#,
        // Hinowa ga CRUSH! 018 (2019) (Digital) (LuCaZ).cbz, Hinowa ga CRUSH! 018.5 (2019) (Digital) (LuCaZ).cbz
        #"^(?<Series>.+?)(?<!Vol)(?<!Vol.)(?<!Volume)\s(\d\s)?(?<Chapter>\d+(?:\.\d+|-\d+)?)(?:\s\(\d{4}\))?(\b|_|-)"#,
        // Tower Of God S01 014 (CBT) (digital).cbz
        #"(?<Series>.*)\sS(?<Volume>\d+)\s(?<Chapter>\d+(?:.\d+|-\d+)?)"#,
        // Beelzebub_01_[Noodles].zip, Beelzebub_153b_RHS.zip
        #"^((?!v|vo|vol|Volume).)*(\s|_)(?<Chapter>\.?\d+(?:.\d+|-\d+)?)(?<Part>b)?(\s|_|\[|\()"#,
        // Yumekui-Merry_DKThias_Chapter21.zip
        #"Chapter(?<Chapter>\d+(-\d+)?)"#,
        // [Hidoi]_Amaenaideyo_MS_vol01_chp02.rar
        #"(?<Series>.*)(\s|_)(vol\d+)?(\s|_)Chp\.? ?(?<Chapter>\d+)"#,
        // Vol 1 Chapter 2
        #"(?<Volume>((vol|volume|v))?(\s|_)?\.?\d+)(\s|_)(Chp|Chapter)\.?(\s|_)?(?<Chapter>\d+)"#,
        // Chinese Chapter: 第n话 -> Chapter n, 【TFO汉化&Petit汉化】迷你偶像漫画第25话
        #"第(?<Chapter>\d+)话"#,
        // Korean Chapter: 제n화 -> Chapter n, 가디언즈 오브 갤럭시 죽음의 보석.E0008.7화#44
        #"제?(?<Chapter>\d+\.?\d+)(회|화|장)"#,
        // Korean Chapter: 第10話 -> Chapter n, [ハレム]ナナとカオル ～高校生のSMごっこ～　第1話
        #"第?(?<Chapter>\d+(?:\.\d+|-\d+)?)話"#,
        // Russian Chapter: n Главa -> Chapter n
        #"(?!Том)(?<!Том\.)\s\d+(\s|_)?(?<Chapter>\d+(?:\.\d+|-\d+)?)(\s|_)(Глава|глава|Главы|Глава)"#
    ]

    // An additional check to avoid situations like "One Piece - Vol 4 ch 2 - vol 6 omakes"
    private static let duplicateVolumeRegex = regex(#"(?i)(vol\.?|volume|v)(\s|_)*\d+.*?(vol\.?|volume|v)(\s|_)*\d+"#)
    private static let duplicateChapterRegex = regex(#"(?i)(ch\.?|chapter|c)(\s|_)*\d+.*?(ch\.?|chapter|c)(\s|_)*\d+"#)
    // Regex to detect range patterns that should NOT be treated as duplicates (History's Strongest c1-c4)
    private static let volumeRangeRegex = regex(#"(vol\.?|v)(\s|_)?\d+(\.\d+)?-(vol\.?|v)(\s|_)?\d+(\.\d+)?"#)
    private static let chapterRangeRegex = regex(#"(ch\.?|c)(\s|_)?\d+(\.\d+)?-(ch\.?|c)(\s|_)?\d+(\.\d+)?"#)
    private static let volumeNumberRegex = regex(#"(vol\.?|volume|v)(\s|_)*(?<Volume>\d+(\.\d+)?(-\d+(\.\d+)?)?)"#)
    private static let chapterNumberRegex = regex(#"(ch\.?|chapter|c)(\s|_)*(?<Chapter>\d+(\.\d+)?(-\d+(\.\d+)?)?)"#)

    private static let mangaEditionRegex = regex(#"\b(?:Omnibus(?:\s?Edition)?|Uncensored)\b"#)
    private static let cleanupRegex = regex(#"(?:\([^()]*\)|\[[^\[\]]*\]|\{[^\{\}]*\}|\{Complete\})"#)
    private static let emptySpaceRegex = regex(#"\s{2,}"#)
}

// MARK: - Helpers
extension LocalFileNameParser {
    // find the first match for any of the given patterns and return a named group value
    private static func firstMatchGroup(_ patterns: [String], in text: String, groupName: String) -> (String?, hasPart: Bool) {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: text, range: text.range())
                for match in matches {
                    if let range = Range(match.range(withName: groupName), in: text), !range.isEmpty {
                        let value = String(text[range])
                        let hasPart = match.range(withName: "Part").location != NSNotFound
                        return (value, hasPart)
                    }
                }
            }
        }
        return (nil, false)
    }

    // removes leading zeros and handles ranges
    private static func formatValue(_ value: String, hasPart: Bool) -> String {
        if !value.contains("-") {
            return removeLeadingZeroes(hasPart ? addChapterPart(value) : value)
        }

        let tokens = value.components(separatedBy: "-")
        let from = removeLeadingZeroes(tokens[0])

        guard tokens.count == 2 else { return from }

        var to = tokens[1]
        if to.lowercased().hasPrefix("c") { // handle "c01-c02"
            to = String(to.dropFirst())
        }
        to = removeLeadingZeroes(hasPart ? addChapterPart(to) : to)
        return "\(from)-\(to)"
    }

    // Translates _ -> spaces, trims front and back of string, and removes release groups
    private static func cleanTitle(_ title: String, isComic: Bool = false) -> String {
        var result = title
        result = result.replacingOccurrences(of: "_", with: " ")
        result = removeEditionTagHolders(result)
        result = result.trimmingCharacters(in: ["\0", "\t", "\r", " ", "-", ","])
        result = emptySpaceRegex.stringByReplacingMatches(in: result, range: result.range(), withTemplate: " ")
        return result
    }

    // Remove leading zeroes from numbers, e.g., "001" -> "1"
    private static func removeLeadingZeroes(_ value: String) -> String {
        let value = if #available(iOS 16.0, macOS 13.0, *) {
            value.trimmingPrefix(while: { $0 == "0" })
        } else {
            value.drop(while: { $0 == "0" })
        }
        if value.isEmpty {
            return "0"
        } else {
            return String(value)
        }
    }

    // appends .5 to chapter numbers that don't have a decimal part
    private static func addChapterPart(_ value: String) -> String {
        if value.contains(".") {
            value
        } else {
            "\(value).5"
        }
    }

    private static func removeEditionTagHolders(_ title: String) -> String {
        var result = title
        result = cleanupRegex.stringByReplacingMatches(in: result, range: result.range(), withTemplate: "")
        result = mangaEditionRegex.stringByReplacingMatches(in: result, range: result.range(), withTemplate: "")
        return result
    }

    // Checks for a duplicate volume marker and removes it
    private static func removeDuplicateVolumeIfExists(_ filename: String) -> String {
        // if this contains a volume range pattern, don't process as duplicate (v1-v2, edge case)
        guard volumeRangeRegex.firstMatch(in: filename, range: filename.range()) == nil else {
            return filename
        }

        // Find the start position of the first volume marker
        guard
            let duplicateMatch = duplicateVolumeRegex.firstMatch(in: filename, range: filename.range()),
            let firstVolumeStart = Range(duplicateMatch.range(at: 1), in: filename)?.lowerBound
        else {
            return filename
        }

        // Find the volume number after the first marker
        guard
            let volumeNumberMatch = volumeNumberRegex.firstMatch(in: filename, range: NSRange(firstVolumeStart..<filename.endIndex, in: filename)),
            let volumeNumberEnd = Range(volumeNumberMatch.range, in: filename)?.upperBound
        else {
            return filename
        }

        // Find the second volume marker after the first volume number
        if let secondVolumeMatch = volumeNumberRegex.firstMatch(in: filename, range: NSRange(volumeNumberEnd..<filename.endIndex, in: filename)) {
            // Truncate the filename at the second volume marker
            let truncateIndex = filename.index(filename.startIndex, offsetBy: secondVolumeMatch.range.location)
            return filename[..<truncateIndex].trimmingCharacters(in: [" ", "-", "_"])
        }

        return filename
    }

    // Removes duplicate chapter markers from filename, keeping only the first occurrence
    private static func removeDuplicateChapterIfExists(_ filename: String) -> String {
        // If this contains a chapter range pattern, don't process as duplicate (c1-c2, edge case)
        guard chapterRangeRegex.firstMatch(in: filename, range: filename.range()) == nil else {
            return filename
        }

        // Find the start position of the first chapter marker
        guard
            let duplicateMatch = duplicateChapterRegex.firstMatch(in: filename, range: filename.range()),
            let firstChapterStart = Range(duplicateMatch.range(at: 1), in: filename)?.lowerBound
        else {
            return filename
        }

        // Find the chapter number after the first marker
        guard
            let chapterNumberMatch = chapterNumberRegex.firstMatch(in: filename, range: NSRange(firstChapterStart..<filename.endIndex, in: filename)),
            let chapterNumberEnd = Range(chapterNumberMatch.range, in: filename)?.upperBound
        else {
            return filename
        }

        // Find the second chapter marker after the first chapter number
        if let secondChapterMatch = chapterNumberRegex.firstMatch(in: filename, range: NSRange(chapterNumberEnd..<filename.endIndex, in: filename)) {
            // Truncate the filename at the second chapter marker
            let truncateIndex = filename.index(filename.startIndex, offsetBy: secondChapterMatch.range.location)
            return filename[..<truncateIndex].trimmingCharacters(in: [" ", "-", "_"])
        }

        return filename
    }

    private static func regex(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }
}

private extension String {
    func range() -> NSRange {
        NSRange(startIndex..., in: self)
    }
}

//
//  ComicInfo.swift
//  Aidoku
//
//  Created by Skitty on 11/11/25.
//

import AidokuRunner
import Foundation
import ZIPFoundation

// https://github.com/anansi-project/comicinfo/blob/main/schema/v2.0/ComicInfo.xsd
struct ComicInfo: Hashable {
    /// Title of the book.
    var title: String?
    /// Title of the series the book is part of.
    var series: String?
    /// Number of the book in the series.
    var number: String?
    /// The total number of books in the series.
    var count: Int?
    /// Volume containing the book.
    var volume: Int?
    /// A description or summary of the book.
    var summary: String?
    /// A free text field, usually used to store information about the application that created the ComicInfo.xml file.
    var notes: String?
    /// The release year of the book.
    var year: Int?
    /// The release month of the book.
    var month: Int?
    /// The release day of the book.
    var day: Int?
    /// Person or organization responsible for creating the scenario (comma separated).
    var writer: String?
    /// Person or organization responsible for drawing the art (comma separated).
    var penciller: String?
    /// A person or organization who renders a text from one language into another (comma separated).
    var translator: String?
    /// Genre of the book or series (comma separated).
    var genre: String?
    /// Tags of the book or series (comma separated).
    var tags: String?
    /// A URL pointing to a reference website for the book (space separated).
    var web: String?
    /// A language code describing the language of the book.
    var languageIso: String?
    /// Whether the book is a manga. This also defines the reading direction as right-to-left when set to YesAndRightToLeft.
    var manga: Manga?
    /// Age rating of the book.
    var ageRating: AgeRating?

    enum AgeRating: String {
        case unknown = "Unknown"
        case everyone = "Everyone"
        case m15Plus = "MA15+"
        case r18Plus = "R18+"
    }

    enum Manga: String {
        case unknown = "Unknown"
        case no = "No"
        case yes = "Yes"
        case yesAndRightToLeft = "YesAndRightToLeft"
    }

    struct AidokuNotesData: Codable {
        static let prefix = "!AIDOKUDATA"

        let sourceKey: String?
        let mangaKey: String?
        let chapterKey: String?
    }
}

extension ComicInfo {
    func extraData() -> AidokuNotesData? {
        guard
            let notes,
            notes.hasPrefix(AidokuNotesData.prefix)
        else {
            return nil
        }
        return try? JSONDecoder().decode(
            AidokuNotesData.self,
            from: Data(notes.dropFirst(AidokuNotesData.prefix.count).utf8)
        )
    }
}

extension ComicInfo {
    static func load(manga: AidokuRunner.Manga, chapter: AidokuRunner.Chapter) -> ComicInfo {
        let dateComponents = chapter.dateUploaded.flatMap { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
        return .init(
            title: chapter.title,
            series: manga.title,
            number: chapter.chapterNumber.flatMap { String(format: "%g", $0) },
            count: nil,
            volume: chapter.volumeNumber.flatMap { Int($0) },
            summary: manga.description,
            notes: (try? JSONEncoder().encode(AidokuNotesData(
                sourceKey: manga.sourceKey,
                mangaKey: manga.key,
                chapterKey: chapter.key
            ))).flatMap {
                String(data: $0, encoding: .utf8).flatMap { AidokuNotesData.prefix + $0 }
            },
            year: dateComponents?.year,
            month: dateComponents?.month,
            day: dateComponents?.day,
            writer: manga.authors?.joined(separator: ", "),
            penciller: manga.artists?.joined(separator: ", "),
            translator: chapter.scanlators?.joined(separator: ", "),
            genre: nil,
            tags: manga.tags?.joined(separator: ", "),
            web: manga.url?.absoluteString,
            languageIso: chapter.language,
            manga: {
                switch manga.viewer {
                    case .rightToLeft: .yesAndRightToLeft
                    case .unknown: nil
                    default: .no
                }
            }(),
            ageRating: {
                switch manga.contentRating {
                    case .unknown: nil
                    case .safe: .everyone
                    case .suggestive: .m15Plus
                    case .nsfw: .r18Plus
                }
            }()
        )
    }

    func toManga() -> AidokuRunner.Manga? {
        guard
            let extraData = extraData(),
            let sourceKey = extraData.sourceKey,
            let key = extraData.mangaKey
        else {
            return nil
        }
        let basicManga = AidokuRunner.Manga(sourceKey: sourceKey, key: key, title: series ?? "")
        return copy(into: basicManga)
    }

    func toChapter() -> AidokuRunner.Chapter? {
        guard
            let extraData = extraData(),
            let key = extraData.chapterKey
        else {
            return nil
        }
        let basicChapter = AidokuRunner.Chapter(key: key)
        return copy(into: basicChapter)
    }

    func copy(into manga: AidokuRunner.Manga) -> AidokuRunner.Manga {
        let artists = penciller.flatMap { $0.commaSeparated() }
        let authors = writer.flatMap { $0.commaSeparated() }
        let url = web?.split(separator: " ", maxSplits: 1).first.flatMap { URL(string: String($0)) }
        let tags = (genre.flatMap { $0.commaSeparated() } ?? []) + (tags.flatMap { $0.commaSeparated() } ?? [])
        let contentRating: ContentRating = switch ageRating {
            case .everyone: .safe
            case .m15Plus: .suggestive
            case .r18Plus: .nsfw
            default: manga.contentRating
        }
        let viewer: Viewer = switch self.manga {
            case .yesAndRightToLeft: .rightToLeft
            default: manga.viewer
        }
        return AidokuRunner.Manga(
            sourceKey: manga.sourceKey,
            key: manga.key,
            title: series ?? manga.title,
            cover: manga.cover,
            artists: (artists?.isEmpty ?? true) ? manga.artists : artists,
            authors: (authors?.isEmpty ?? true) ? manga.authors : authors,
            description: summary ?? manga.description,
            url: url ?? manga.url,
            tags: tags.isEmpty ? manga.tags : tags,
            status: manga.status,
            contentRating: contentRating,
            viewer: viewer,
            updateStrategy: manga.updateStrategy,
            nextUpdateTime: manga.nextUpdateTime,
            chapters: manga.chapters
        )
    }

    func copy(into chapter: AidokuRunner.Chapter) -> AidokuRunner.Chapter {
        let dateUploaded: Date? = {
            guard let day, let month, let year else { return nil }
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            return Calendar.current.date(from: components)
        }()
        let scanlators = translator.flatMap { $0.commaSeparated() }
        let url = web?.split(separator: " ", maxSplits: 1).first.flatMap { URL(string: String($0)) }
        return AidokuRunner.Chapter(
            key: chapter.key,
            title: title ?? chapter.title,
            chapterNumber: number.flatMap { Float($0) } ?? chapter.chapterNumber,
            volumeNumber: volume.flatMap { Float($0) } ?? chapter.volumeNumber,
            dateUploaded: dateUploaded ?? chapter.dateUploaded,
            scanlators: (scanlators?.isEmpty ?? true) ? chapter.scanlators : scanlators,
            url: url ?? chapter.url,
            language: languageIso ?? chapter.language,
            thumbnail: chapter.thumbnail,
            locked: chapter.locked
        )
    }
}

extension ComicInfo {
    static func load(xmlString: String) -> ComicInfo? {
        guard let data = xmlString.data(using: .utf8) else {
            return nil
        }

        class ComicInfoParserDelegate: NSObject, XMLParserDelegate {
            var currentElement: String?
            var currentValue: String = ""

            var title: String?
            var series: String?
            var number: String?
            var count: Int?
            var volume: Int?
            var summary: String?
            var notes: String?
            var year: Int?
            var month: Int?
            var day: Int?
            var writer: String?
            var penciller: String?
            var translator: String?
            var genre: String?
            var tags: String?
            var web: String?
            var pageCount: Int?
            var languageIso: String?
            var manga: ComicInfo.Manga?
            var ageRating: ComicInfo.AgeRating?

            func parser(
                _ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]
            ) {
                currentElement = elementName
                currentValue = ""
            }

            func parser(_ parser: XMLParser, foundCharacters string: String) {
                currentValue += string
            }

            func parser(
                _ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?
            ) {
                let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    switch elementName {
                        case "Title": title = value
                        case "Series": series = value
                        case "Number": number = value
                        case "Count": count = Int(value)
                        case "Volume": volume = Int(value)
                        case "Summary": summary = value
                        case "Notes": notes = value
                        case "Year": year = Int(value)
                        case "Month": month = Int(value)
                        case "Day": day = Int(value)
                        case "Writer": writer = value
                        case "Penciller": penciller = value
                        case "Translator": translator = value
                        case "Genre": genre = value
                        case "Tags": tags = value
                        case "Web": web = value
                        case "LanguageISO": languageIso = value
                        case "Manga": manga = ComicInfo.Manga(rawValue: value)
                        case "AgeRating": ageRating = ComicInfo.AgeRating(rawValue: value)
                        default: break
                    }
                }
                currentElement = nil
                currentValue = ""
            }
        }

        let delegate = ComicInfoParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }

        return ComicInfo(
            title: delegate.title,
            series: delegate.series,
            number: delegate.number,
            count: delegate.count,
            volume: delegate.volume,
            summary: delegate.summary,
            notes: delegate.notes,
            year: delegate.year,
            month: delegate.month,
            day: delegate.day,
            writer: delegate.writer,
            penciller: delegate.penciller,
            translator: delegate.translator,
            genre: delegate.genre,
            tags: delegate.tags,
            web: delegate.web,
            languageIso: delegate.languageIso,
            manga: delegate.manga,
            ageRating: delegate.ageRating
        )
    }

    func export() -> String {
        func xmlEscape(_ string: String) -> String {
            var escaped = string
            escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
            escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
            escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
            escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
            escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
            return escaped
        }

        func xmlElement(_ name: String, _ value: String?) -> String {
            guard let value, !value.isEmpty else { return "" }
            return "    <\(name)>\(xmlEscape(value))</\(name)>\n"
        }

        func xmlElementInt(_ name: String, _ value: Int?) -> String {
            guard let value else { return "" }
            return "    <\(name)>\(value)</\(name)>\n"
        }

        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ComicInfo>\n"
        xml += xmlElement("Title", title)
        xml += xmlElement("Series", series)
        xml += xmlElement("Number", number)
        xml += xmlElementInt("Count", count)
        xml += xmlElementInt("Volume", volume)
        xml += xmlElement("Summary", summary)
        xml += xmlElement("Notes", notes)
        xml += xmlElementInt("Year", year)
        xml += xmlElementInt("Month", month)
        xml += xmlElementInt("Day", day)
        xml += xmlElement("Writer", writer)
        xml += xmlElement("Penciller", penciller)
        xml += xmlElement("Translator", translator)
        xml += xmlElement("Genre", genre)
        xml += xmlElement("Tags", tags)
        xml += xmlElement("Web", web)
        xml += xmlElement("LanguageISO", languageIso)
        xml += xmlElement("Manga", manga?.rawValue)
        xml += xmlElement("AgeRating", ageRating?.rawValue)
        xml += "</ComicInfo>\n"
        return xml
    }
}

extension ComicInfo {
    static func load(from archiveURL: URL) -> ComicInfo? {
        do {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            return load(from: archive)
        } catch {
            return nil
        }
    }

    static func load(from archive: Archive) -> ComicInfo? {
        do {
            guard
                let entry = archive.first(where: { $0.path.hasSuffix("ComicInfo.xml") })
            else {
                return nil
            }
            var data = Data()
            _ = try archive.extract(
                entry,
                consumer: { readData in
                    data.append(readData)
                }
            )
            guard
                let string = String(data: data, encoding: .utf8),
                let comicInfo = ComicInfo.load(xmlString: string)
            else {
                return nil
            }
            return comicInfo
        } catch {
            return nil
        }
    }
}

private extension String {
    func commaSeparated() -> [String] {
        components(separatedBy: ",")
            .compactMap {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return trimmed
            }
    }
}

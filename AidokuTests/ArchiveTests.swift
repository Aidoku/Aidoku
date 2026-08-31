//
//  ArchiveTests.swift
//  Aidoku
//

import Foundation
import Testing
import ZIPFoundation
@testable import Aidoku

@Suite struct ArchiveTests {
    /// Builds an archive on disk containing one entry per given path.
    private func makeArchive(paths: [String]) throws -> (Archive, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        let archive = try Archive(url: url, accessMode: .create)
        let data = Data("contents".utf8)
        for path in paths {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                provider: { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                }
            )
        }
        return (archive, url)
    }

    @Test("Entries written with a ./ prefix resolve")
    func resolvesDotSlashPrefix() throws {
        let (archive, url) = try makeArchive(paths: ["./OEBPS/ch1.xhtml"])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(archive["OEBPS/ch1.xhtml"] == nil)
        #expect(archive.entry(at: "OEBPS/ch1.xhtml") != nil)
    }

    @Test("Percent-encoded entries resolve from a decoded path")
    func resolvesPercentEncodedEntry() throws {
        let (archive, url) = try makeArchive(paths: ["OEBPS/images/plate%20one.png"])
        defer { try? FileManager.default.removeItem(at: url) }

        // EpubParser.resolve(href:relativeTo:) decodes every href, so lookups
        // arrive decoded even when the archive stored the entry encoded
        #expect(archive["OEBPS/images/plate one.png"] == nil)
        #expect(archive.entry(at: "OEBPS/images/plate one.png") != nil)
    }

    @Test("A ./ prefixed entry resolves from a decoded path")
    func resolvesDotSlashPrefixWithSpace() throws {
        let (archive, url) = try makeArchive(paths: ["./OEBPS/images/plate one.png"])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(archive["OEBPS/images/plate one.png"] == nil)
        #expect(archive.entry(at: "OEBPS/images/plate one.png") != nil)
    }

    @Test("Lookup is case insensitive")
    func resolvesDifferingCase() throws {
        let (archive, url) = try makeArchive(paths: ["OEBPS/Cover.PNG"])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(archive.entry(at: "OEBPS/cover.png") != nil)
    }

    @Test("An exact match is returned unchanged")
    func prefersExactMatch() throws {
        let (archive, url) = try makeArchive(paths: ["OEBPS/ch1.xhtml"])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(archive.entry(at: "OEBPS/ch1.xhtml")?.path == "OEBPS/ch1.xhtml")
    }

    @Test("A genuinely absent path returns nil")
    func returnsNilWhenAbsent() throws {
        let (archive, url) = try makeArchive(paths: ["OEBPS/ch1.xhtml"])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(archive.entry(at: "OEBPS/missing.xhtml") == nil)
    }
}

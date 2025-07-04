//
//  DownloadedMangaInfo.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import Foundation

/// Information about a downloaded manga with metadata and size details
struct DownloadedMangaInfo: Identifiable, Hashable {
    let id: String
    let sourceId: String
    let mangaId: String          // actual manga ID from CoreData
    let directoryMangaId: String // sanitized manga ID used for directory name
    let title: String?           // from CoreData if available
    let coverUrl: String?        // from CoreData if available
    let totalSize: Int64
    let chapterCount: Int
    let isInLibrary: Bool

    /// Computed property for display title (fallback to manga ID)
    var displayTitle: String {
        title ?? mangaId
    }

    /// Computed property for formatted size string
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    init(
        sourceId: String,
        mangaId: String,
        directoryMangaId: String? = nil,
        title: String? = nil,
        coverUrl: String? = nil,
        totalSize: Int64,
        chapterCount: Int,
        isInLibrary: Bool
    ) {
        self.id = "\(sourceId)_\(mangaId)"
        self.sourceId = sourceId
        self.mangaId = mangaId
        self.directoryMangaId = directoryMangaId ?? mangaId
        self.title = title
        self.coverUrl = coverUrl
        self.totalSize = totalSize
        self.chapterCount = chapterCount
        self.isInLibrary = isInLibrary
    }
}

/// Information about a downloaded chapter with size details
struct DownloadedChapterInfo: Identifiable, Hashable {
    let id: String
    let chapterId: String
    let title: String?
    let chapterNumber: Float?    // For formatted titles
    let volumeNumber: Float?     // For formatted titles
    let size: Int64
    let downloadDate: Date?

    /// Computed property for display title with smart formatting
    var displayTitle: String {
        // If we have a proper title, use it
        if let title = title, !title.isEmpty {
            return title
        }

        // Try to format using chapter/volume numbers like the app normally does
        if let chapterNumber = chapterNumber {
            if let volumeNumber = volumeNumber {
                return String(
                    format: NSLocalizedString("VOL_X", comment: "") + " " + NSLocalizedString("CH_X", comment: ""),
                    volumeNumber,
                    chapterNumber
                )
            } else {
                return String(format: NSLocalizedString("CHAPTER_X", comment: ""), chapterNumber)
            }
        } else if let volumeNumber = volumeNumber {
            return String(format: NSLocalizedString("VOLUME_X", comment: ""), volumeNumber)
        }

        // Try to extract chapter number from chapterId as last resort
        if let extractedNumber = extractChapterNumber(from: chapterId) {
            return String(format: NSLocalizedString("CHAPTER_X", comment: ""), extractedNumber)
        }

        // Final fallback to chapter ID
        return chapterId
    }

    /// Extract chapter number from chapter ID string as a last resort
    private func extractChapterNumber(from chapterId: String) -> Float? {
        // Look for patterns like "chapter-1", "ch1", "1", etc.
        let patterns = [
            #"chapter[-_]?(\d+(?:\.\d+)?)"#,
            #"ch[-_]?(\d+(?:\.\d+)?)"#,
            #"^(\d+(?:\.\d+)?)$"#,
            #"(\d+(?:\.\d+)?)$"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: chapterId, range: NSRange(chapterId.startIndex..., in: chapterId)),
               let range = Range(match.range(at: 1), in: chapterId) {
                let numberString = String(chapterId[range])
                if let number = Float(numberString) {
                    return number
                }
            }
        }

        return nil
    }

    /// Computed property for formatted size string
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    init(chapterId: String, title: String? = nil, chapterNumber: Float? = nil, volumeNumber: Float? = nil, size: Int64, downloadDate: Date? = nil) {
        self.id = chapterId
        self.chapterId = chapterId
        self.title = title
        self.chapterNumber = chapterNumber
        self.volumeNumber = volumeNumber
        self.size = size
        self.downloadDate = downloadDate
    }
}

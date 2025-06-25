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
    
    init(sourceId: String, mangaId: String, directoryMangaId: String? = nil, title: String? = nil, coverUrl: String? = nil, totalSize: Int64, chapterCount: Int, isInLibrary: Bool) {
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
    let size: Int64
    let downloadDate: Date?
    
    /// Computed property for display title (fallback to chapter ID)
    var displayTitle: String {
        title ?? chapterId
    }
    
    /// Computed property for formatted size string
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    init(chapterId: String, title: String? = nil, size: Int64, downloadDate: Date? = nil) {
        self.id = chapterId
        self.chapterId = chapterId
        self.title = title
        self.size = size
        self.downloadDate = downloadDate
    }
} 
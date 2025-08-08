//
//  LocalModels.swift
//  Aidoku
//
//  Created by Skitty on 6/10/25.
//

import Foundation

enum LocalFileManagerError: Error {
    case invalidFileType
    case tempDirectoryUnavailable
    case cannotReadArchive
    case noImagesFound
    case fileCopyFailed
}

struct LocalSeriesInfo: Hashable {
    let coverUrl: String
    let name: String
    let chapterCount: Int
}

enum LocalFileType {
    case cbz
    case zip

    var localizedName: String {
        switch self {
            case .cbz: NSLocalizedString("CBZ_NAME")
            case .zip: NSLocalizedString("ZIP_NAME")
        }
    }
}

struct ImportFileInfo: Hashable {
    let url: URL
    let previewImages: [PlatformImage]
    let name: String
    let pageCount: Int
    let fileType: LocalFileType
}

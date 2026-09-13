//
//  EpubZipResourceProvider.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import ZIPFoundation

// entries are read on demand, the actor serialising reads onto Archive's single file handle
final actor EpubZipResourceProvider: EpubResourceProvider {
    private let archive: Archive

    init(url: URL) throws {
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw EpubResourceError.cannotOpenArchive(url)
        }
    }

    func data(at path: String) throws -> Data {
        guard let entry = archive.entry(at: path) else {
            throw EpubResourceError.notFound(path)
        }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
        } catch {
            throw EpubResourceError.unreadable(path)
        }
        return data
    }
}

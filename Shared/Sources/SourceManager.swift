//
//  SourceManager.swift
//  Aidoku
//
//  Created by Skitty on 1/10/22.
//

import Foundation
import ZIPFoundation

class SourceManager {
    
    static let shared = SourceManager()
    
    static let directory = FileManager.default.documentDirectory.appendingPathComponent("Sources", isDirectory: true)
    
    var sources: [Source] = []
    
    init() {
        sources = (try? DataManager.shared.getSourceObjects())?.compactMap { $0.toSource() } ?? []
        sources.sort { $0.info.name < $1.info.name }
        
        Task {
            for source in sources {
                _ = try? await source.getFilters()
            }
            NotificationCenter.default.post(name: Notification.Name("loadedSourceFilters"), object: nil)
        }
    }
    
    func source(for id: String) -> Source? {
        sources.first { $0.info.id == id }
    }
    
    func hasSourceInstalled(id: String) -> Bool {
        sources.firstIndex { $0.info.id == id } != nil
    }
    
    func importSource(from url: URL) async -> Source? {
        Self.directory.createDirctory()
        
        var fileUrl = url
    
        if let temporaryDirectory = FileManager.default.temporaryDirectory {
            if fileUrl.scheme != "file" {
                do {
                    let location = try await URLSession.shared.download(for: URLRequest.from(url))
                    fileUrl = location
                } catch {
                    return nil
                }
            }
            try? FileManager.default.unzipItem(at: fileUrl, to: temporaryDirectory)
            try? FileManager.default.removeItem(at: fileUrl)

            let payload = temporaryDirectory.appendingPathComponent("Payload")
            let source = try? Source(from: payload)
            if let source = source {
                let destination = Self.directory.appendingPathComponent(source.info.id)
                if destination.exists {
                    try? FileManager.default.removeItem(at: destination)
                    sources.removeAll { $0.id == source.id }
                }
                try? FileManager.default.moveItem(at: payload, to: destination)
                try? FileManager.default.removeItem(at: temporaryDirectory)
                
                source.url = destination
                
                if let _ = DataManager.shared.add(source: source) {
                    sources.append(source)
                    sources.sort { $0.info.name < $1.info.name }
                    
                    NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
                    
                    Task {
                        _ = try? await source.getFilters()
                    }
                    
                    return source
                }
            }
        }
        
        return nil
    }
    
    func clearSources() {
        for source in sources {
            try? FileManager.default.removeItem(at: source.url)
        }
        sources = []
        DataManager.shared.clearSources()
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
    
    func remove(source: Source) {
        try? FileManager.default.removeItem(at: source.url)
        DataManager.shared.delete(source: source)
        sources.removeAll { $0.id == source.id }
        NotificationCenter.default.post(name: Notification.Name("updateSourceList"), object: nil)
    }
}

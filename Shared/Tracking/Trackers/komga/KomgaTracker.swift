//
//  KomgaTracker.swift
//  Aidoku
//
//  Created by Paolo Casellati on 07/10/23.
//

import Foundation

#if os(OSX)
    import AppKit
#else
    import UIKit
#endif

/// AniList tracker for Aidoku.
class KomgaTracker: Tracker {
    var isLoggedIn: Bool
    var baseurl: String
    var searchurl: String
    var thumburl: String
    var serieurl: String
    var statusurl: String
    var seriewebsurl: String

    var usr: String
    var pwd: String
    
    /// A unique identification string.
    let id = "komga"
    
    /// The title of the tracker.
    let name = "Komga"
    
    /// The icon of the tracker.
    let icon = UIImage(named: "komga")

    /// An array of track statuses the tracker supports.
    let supportedStatuses = TrackStatus.defaultStatuses
    
    /// The current score type for the tracker.
    var scoreType: TrackScoreType = .tenPoint
    
    func logout() {
        
    }
    
    init() {
        isLoggedIn = true
        usr = "demo@komga.org"
        pwd = "komga-demo"
        baseurl = "https://demo.komga.org"
        searchurl = baseurl + "/api/v1/series"
        thumburl = baseurl + "/api/v1/series/%@/thumbnail"
        serieurl = baseurl + "/api/v1/series/%@"
        statusurl = baseurl + "/api/v2/series/%@/read-progress/tachiyomi"
        seriewebsurl = baseurl + "series/%@"
    }
    
    func option(for score: Int) -> String? {
        return nil
    }

    func register(trackId: String, hasReadChapters: Bool) async {
        // Should do nothing
        print("Register: " + trackId + " Read: " + String(hasReadChapters))
    }

    func update(trackId: String, update: TrackUpdate) async {
        let loginString = String(format: "%@:%@", usr, pwd)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let url = URL(string: String(format: statusurl, trackId))!
        
        let json: [String: Any] = ["lastBookNumberSortRead": update.lastReadChapter ?? 0]
        let jsonData = try? JSONSerialization.data(withJSONObject: json)

        var request = URLRequest(url: url)
        request.httpBody = jsonData
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        self.createRequest(request: request) { (jsonString) in
            print(jsonString)
        }
    }

    func getState(trackId: String) async -> TrackState {
        var res: TrackState = TrackState()
        
        let loginString = String(format: "%@:%@", usr, pwd)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let urlComponents = URLComponents(string: String(format: statusurl, trackId))!
        
        if let url = urlComponents.url {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            self.createRequest(request: request) { (jsonString) in
                let jsonData = jsonString.data(using: .utf8)!
                let state: KomgaStatusResultManga = try! JSONDecoder().decode(KomgaStatusResultManga.self, from: jsonData)

                res = TrackState(
                    score: 10,
                    status: self.getStatus(status: state),
                    lastReadChapter: Float(state.booksReadCount),
                    lastReadVolume: 0,
                    totalChapters: state.booksCount,
                    totalVolumes: 0,
                    startReadDate: nil,
                    finishReadDate: nil
                )
            }
        }
        return res
    }

    func getUrl(trackId: String) -> URL? {
        return URL(string: String(format: seriewebsurl, trackId))
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        print("Search Manga")
        
        let res = await get_serie(id: manga.id)
        if res != nil
        {
            return [res!]
        }
        else
        {
            return await search(title: manga.title ?? "")
        }
    }

    func search(title: String) async -> [TrackSearchItem] {
        var res: [TrackSearchItem] = []
        
        let loginString = String(format: "%@:%@", usr, pwd)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        var urlComponents = URLComponents(string: searchurl)!

        urlComponents.queryItems = [
            URLQueryItem(name: "search", value: title)
        ]
        
        if let url = urlComponents.url {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            self.createRequest(request: request) { (jsonString) in
                let jsonData = jsonString.data(using: .utf8)!
                let mangas: KomgaSearchResultManga = try! JSONDecoder().decode(KomgaSearchResultManga.self, from: jsonData)
                for manga : KomgaSearchResultContentManga in mangas.content
                {
                    res.append(TrackSearchItem(
                        id: manga.id,
                        trackerId: self.id,
                        title: manga.metadata.title,
                        coverUrl: String(format: self.thumburl, arguments: [manga.id]),
                        description: manga.metadata.summary,
                        status: self.getPublishingStatus(statusString: manga.metadata.status),
                        type: MediaType.manga, // How should i know?
                        tracked: false // How should i know?
                    ))
                }
            }
        }
        return res
    }
    
    func get_serie(id: String) async -> TrackSearchItem? {
        var res: TrackSearchItem? = nil
        
        let loginString = String(format: "%@:%@", usr, pwd)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let urlComponents = URLComponents(string: String(format: serieurl, id))!
        
        if let url = urlComponents.url {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            self.createRequest(request: request) { (jsonString) in
                let jsonData = jsonString.data(using: .utf8)!
                let manga: KomgaSearchResultContentManga = try! JSONDecoder().decode(KomgaSearchResultContentManga.self, from: jsonData)

                res = TrackSearchItem(
                    id: manga.id,
                    trackerId: self.id,
                    title: manga.metadata.title,
                    coverUrl: String(format: self.thumburl, arguments: [manga.id]),
                    description: manga.metadata.summary,
                    status: self.getPublishingStatus(statusString: manga.metadata.status),
                    type: MediaType.manga, // How should i know?
                    tracked: false // How should i know?
                )
            }
        }
        return res
    }
}

private extension KomgaTracker {

    func getStatus(status: KomgaStatusResultManga) -> TrackStatus {
        if status.booksCount == status.booksReadCount {
                return .completed
        } else if status.booksReadCount > 0 {
            return .reading
        } else {
            return .planning
        }
    }

    func getPublishingStatus(statusString: String) -> PublishingStatus {
        switch statusString {
        case "ENDED": return .completed
        case "ONGOING": return .ongoing
        case "ABANDONED": return .cancelled
        case "HIATUS": return .hiatus
        default: return .unknown
        }
    }

    private func decodeDate(_ value: AniListDate?) -> Date? {
        if let day = value?.day, let month = value?.month, let year = value?.year {
            return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        }
        return nil
    }
    
    func createRequest(request: URLRequest, completionBlock: @escaping (String) -> Void) -> Void
    {
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard
                error == nil,
                let data = data
            else {
                print(error ?? "Unknown error")
                return
            }
            let outputStr  = String(data: data, encoding: String.Encoding.utf8)!
            completionBlock(outputStr)
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .distantFuture)
    }
}

struct KomgaSearchResultManga: Decodable
{
    let content: [KomgaSearchResultContentManga]
}

struct KomgaSearchResultContentManga: Decodable
{
    let id: String
    let libraryId: String
    let name: String
    let url: String
//    let created: Date
//    let lastModified: Date
//    let fileLastModified: Date
    let metadata: KomgaSearcResultContentMetadataManga
}

struct KomgaSearcResultContentMetadataManga: Decodable
{
    let status: String
    let title: String
    let titleSort: String
    let summary: String
    let readingDirection: String
    let publisher: String
    let ageRating: Int?
    let language: String
}

struct KomgaStatusResultManga: Decodable
{
  let booksCount: Int
  let booksReadCount: Int
  let booksUnreadCount: Int
  let booksInProgressCount: Int
  let lastReadContinuousNumberSort: Float
  let maxNumberSort: Float
}

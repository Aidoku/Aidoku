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
class KomgaTracker: HostUserPassTracker {
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
    
    func login(host: String, user: String, pass: String) async -> Bool {
        var res = false
        let loginString = String(format: "%@:%@", user, pass)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let url = URL(string: getSeriesUrl(host: host)!)!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        self.createRequest(request: request) { (_, response, error) in
            if error == nil && response != nil && response?.statusCode == 200 {
                res = true
                self.hostname = host
                self.username = user
                self.password = pass
            }
        }
        return res
    }
        
    init() {
//        isLoggedIn = true
//        usr = "demo@komga.org"
//        pwd = "komga-demo"
    }
    
    func option(for score: Int) -> String? {
        return nil
    }

    func register(trackId: String, hasReadChapters: Bool) async {
        // Should do nothing
        print("Register: " + trackId + " Read: " + String(hasReadChapters))
    }

    func update(trackId: String, update: TrackUpdate) async {
        let loginString = String(format: "%@:%@", username!, password!)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let url = URL(string: getStatusUrl(id: trackId)!)!
        
        let json: [String: Any] = ["lastBookNumberSortRead": update.lastReadChapter ?? 0]
        let jsonData = try? JSONSerialization.data(withJSONObject: json)

        var request = URLRequest(url: url)
        request.httpBody = jsonData
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        
        self.createRequest(request: request) { (jsonString, _, _) in
            print(jsonString!)
        }
    }

    func getState(trackId: String) async -> TrackState {
        var res: TrackState = TrackState()
        
        let loginString = String(format: "%@:%@", username!, password!)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let urlComponents = URLComponents(string: getStatusUrl(id: trackId)!)!
        
        if let url = urlComponents.url {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            self.createRequest(request: request) { (jsonString, _, _) in
                let jsonData = jsonString!.data(using: .utf8)!
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
        return URL(string: getSerieWebUrl(id: trackId)!)
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
        
        let loginString = String(format: "%@:%@", username!, password!)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        var urlComponents = URLComponents(string: getSeriesUrl()!)!

        urlComponents.queryItems = [
            URLQueryItem(name: "search", value: title)
        ]
        
        if let url = urlComponents.url {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            self.createRequest(request: request) { (jsonString, _, _) in
                let jsonData = jsonString!.data(using: .utf8)!
                let mangas: KomgaSearchResultManga = try! JSONDecoder().decode(KomgaSearchResultManga.self, from: jsonData)
                for manga : KomgaSearchResultContentManga in mangas.content
                {
                    res.append(TrackSearchItem(
                        id: manga.id,
                        trackerId: self.id,
                        title: manga.metadata.title,
                        coverUrl: self.getThumbUrl(id: manga.id),
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
        
        let loginString = String(format: "%@:%@", username!, password!)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        let urlComponents = URLComponents(string: getSerieUrl(id: id)!)!
        
        if let url = urlComponents.url {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            
            self.createRequest(request: request) { (jsonString, response, error) in
                if error == nil && response != nil && response?.statusCode == 200 {
                    let jsonData = jsonString!.data(using: .utf8)!
                    let manga: KomgaSearchResultContentManga = try! JSONDecoder().decode(KomgaSearchResultContentManga.self, from: jsonData)
                    
                    res = TrackSearchItem(
                        id: manga.id,
                        trackerId: self.id,
                        title: manga.metadata.title,
                        coverUrl: self.getThumbUrl(id: manga.id),
                        description: manga.metadata.summary,
                        status: self.getPublishingStatus(statusString: manga.metadata.status),
                        type: MediaType.manga, // How should i know?
                        tracked: false // How should i know?
                    )
                }
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
    
    func createRequest(request: URLRequest, completionBlock: @escaping (String?, HTTPURLResponse?, Error?) -> Void) -> Void
    {
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var outputStr: String? = nil
            let response = response as? HTTPURLResponse
            let error = error
            if error == nil {
                let data = data
                outputStr = String(data: data!, encoding: String.Encoding.utf8)
            } else
            {
                outputStr = nil
            }
            completionBlock(outputStr, response, error)
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .distantFuture)
    }
    
    func getSeriesUrl(host: String? = nil) -> String? {
        if host != nil
        {
            return host! + "/api/v1/series"
        } else if hostname != nil
        {
            return hostname! + "/api/v1/series"
        }
        else
        {
            return nil
        }
    }

    func getThumbUrl(host: String? = nil, id: String? = nil) -> String? {
        var suffix = "/api/v1/series/%@/thumbnail"
        if id != nil
        {
            suffix = String(format: suffix, id!)
        }

        if host != nil
        {
            return host! + suffix
        } else if hostname != nil
        {
            return hostname! + suffix
        }
        else
        {
            return nil
        }
    }

    func getSerieUrl(host: String? = nil, id: String? = nil) -> String? {
        var suffix = "/api/v1/series/%@"
        if id != nil
        {
            suffix = String(format: suffix, id!)
        }
        
        if host != nil
        {
            return host! + suffix
        } else if hostname != nil
        {
            return hostname! + suffix
        }
        else
        {
            return nil
        }
    }

    func getStatusUrl(host: String? = nil, id: String? = nil) -> String? {
        var suffix = "/api/v2/series/%@/read-progress/tachiyomi"
        if id != nil
        {
            suffix = String(format: suffix, id!)
        }
        
        if host != nil
        {
            return host! + suffix
        } else if hostname != nil
        {
            return hostname! + suffix
        }
        else
        {
            return nil
        }
    }
    
    func getSerieWebUrl(host: String? = nil, id: String? = nil) -> String? {
        var suffix = "series/%@"
        if id != nil
        {
            suffix = String(format: suffix, id!)
        }
        
        if host != nil
        {
            return host! + suffix
        } else if hostname != nil
        {
            return hostname! + suffix
        }
        else
        {
            return nil
        }
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

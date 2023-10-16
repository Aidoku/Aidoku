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

/// Komga tracker for Aidoku.
class KomgaTracker: HostUserPassTracker {

    let id = "komga"
    let name = "Komga"
    let icon = UIImage(named: "komga")

    let supportedStatuses = TrackStatus.defaultStatuses

    var scoreType: TrackScoreType = .tenPoint

    func login(host: String, user: String, pass: String) async -> Bool {
        if await tryLogin(host: host, user: user, pass: pass) {
            self.hostname = host
            self.username = user
            self.password = pass
            return true
        } else
        {
            return false
        }
    }

    func option(for score: Int) -> String? {
        nil
    }

    func register(trackId: String, hasReadChapters: Bool) async {
        // Should do nothing
    }

    func update(trackId: String, update: TrackUpdate) async {
        _ = await updateSerie(trackId: trackId, update: update)
    }

    func getState(trackId: String) async -> TrackState {
        let res = await getStatus(id: trackId)

        if let r = res {
            return TrackState(
                score: 10,
                status: self.getStatus(status: r),
                lastReadChapter: Float(r.booksReadCount),
                lastReadVolume: 0,
                totalChapters: r.booksCount,
                totalVolumes: 0,
                startReadDate: nil,
                finishReadDate: nil
            )
        } else
        {
            return TrackState()
        }
    }

    func getUrl(trackId: String) -> URL? {
        URL(string: getSerieWebUrl(id: trackId)!)
    }

    func search(for manga: Manga) async -> [TrackSearchItem] {
        let res = await getSerie(id: manga.id)
        if let r = res
        {
            return [TrackSearchItem(
                id: r.id,
                trackerId: self.id,
                title: r.metadata.title,
                coverUrl: self.getThumbUrl(id: manga.id),
                description: r.metadata.summary,
                status: self.getPublishingStatus(statusString: r.metadata.status),
                type: MediaType.manga, // How should i know?
                tracked: false // How should i know?
            )]
        } else
        {
            return await search(title: manga.title ?? "")
        }
    }

    func search(title: String) async -> [TrackSearchItem] {
        let mangas = await searchSerie(title: title)
        var res: [TrackSearchItem] = []
        for manga in mangas {
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
        return res
    }
}

extension KomgaTracker {

    func tryLogin(host: String, user: String, pass: String) async -> Bool {
        var res = false

        let loginString = String(format: "%@:%@", user, pass)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()

        if let url = URL(string: getSeriesUrl(host: host)!) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")

            self.createRequest(request: request) { _, response, error in
                if error == nil && response != nil && response?.statusCode == 200 {
                    res = true
                }
            }
        }
        return res
    }

    func updateSerie(trackId: String, update: TrackUpdate) async -> Bool {
        var res = false

        if let url = URL(string: getStatusUrl(id: trackId)!) {

            let json: [String: Any] = ["lastBookNumberSortRead": update.lastReadChapter ?? 0]
            let jsonData = try? JSONSerialization.data(withJSONObject: json)

            var request = generateURLRequest(url: url, method: "PUT")
            request.httpBody = jsonData

            self.createRequest(request: request) { _, _, error in
                if error == nil {
                    res = true
                }
            }
        }
        return res
    }

    func getStatus(id: String) async -> KomgaStatusResultManga? {
        var res: KomgaStatusResultManga?

        if let url = URL(string: getStatusUrl(id: id)!) {

            let request = generateURLRequest(url: url, method: "GET")

            self.createRequest(request: request) { jsonString, _, _ in
                let jsonData = jsonString!.data(using: .utf8)!
                do {
                    let state: KomgaStatusResultManga = try JSONDecoder().decode(KomgaStatusResultManga.self, from: jsonData)
                    res = state
                } catch {}
            }
        }
        return res
    }

    func searchSerie(title: String) async -> [KomgaSearchResultContentManga] {
        var res: [KomgaSearchResultContentManga] = []

        var urlComponents = URLComponents(string: getSeriesUrl()!)!

        urlComponents.queryItems = [
            URLQueryItem(name: "search", value: title)
        ]

        if let url = urlComponents.url {
            let request = generateURLRequest(url: url, method: "GET")

            self.createRequest(request: request) { jsonString, _, _ in
                let jsonData = jsonString!.data(using: .utf8)!
                do {
                    let mangas: KomgaSearchResultManga = try JSONDecoder().decode(KomgaSearchResultManga.self, from: jsonData)
                    res = mangas.content
                } catch {}
            }
        }
        return res
    }

    func getSerie(id: String) async -> KomgaSearchResultContentManga? {
        var res: KomgaSearchResultContentManga?

        if let url = URL(string: getSerieUrl(id: id)!) {

            let request = generateURLRequest(url: url, method: "GET")

            self.createRequest(request: request) { jsonString, response, error in
                if error == nil && response != nil && response?.statusCode == 200 {
                    let jsonData = jsonString!.data(using: .utf8)!
                    do {
                        let manga: KomgaSearchResultContentManga = try JSONDecoder().decode(KomgaSearchResultContentManga.self, from: jsonData)
                        res = manga
                    } catch {}
                }
            }
        }
        return res
    }
}

private extension KomgaTracker {
    func generateURLRequest(url: URL, method: String) -> URLRequest {
        let loginString = String(format: "%@:%@", username!, password!)
        let loginData = loginString.data(using: String.Encoding.utf8)!
        let base64LoginString = loginData.base64EncodedString()
        var request = URLRequest(url: url)
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
        request.httpMethod = method
        return request
    }

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

    func createRequest(request: URLRequest, completionBlock: @escaping (String?, HTTPURLResponse?, Error?) -> Void)
    {
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            var outputStr: String?
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
        } else
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
        } else
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
        } else
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
        } else
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
        } else
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

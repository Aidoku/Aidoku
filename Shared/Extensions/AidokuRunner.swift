//
//  AidokuRunner.swift
//  Aidoku
//
//  Created by Skitty on 8/24/23.
//

import AidokuRunner
import Foundation

extension InterpreterConfiguration {
    static func defaultConfig(for sourceId: String) -> Self {
        .init(
            printHandler: { message in
                LogManager.logger.log("[\(sourceId)] \(message)")
            },
            requestHandler: { originalRequest in
                let request = if let url = originalRequest.url {
                    await AidokuRunner.Source.modify(url: url, request: originalRequest)
                } else {
                    originalRequest
                }

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)

                    let isCloudflare = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Server") == "cloudflare"
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1

                    // check if cloudflare blocked the request
                    if isCloudflare && (code == 503 || code == 403 || code == 429) {
                        // handle cloudflare
                        await CloudflareHandler.shared.handle(request: request)

                        // retry request
                        let newRequest = if let url = originalRequest.url {
                            await AidokuRunner.Source.modify(url: url, request: originalRequest)
                        } else {
                            originalRequest
                        }
                        return try await URLSession.shared.data(for: newRequest)
                    }

                    return (data, response)
                } catch {
                    throw error
                }
            }
        )
    }
}

extension AidokuRunner.Source {
    convenience init(id: String, url: URL) async throws {
        try await self.init(
            url: url,
            interpreterConfig: .defaultConfig(for: id)
        )
    }

    func toInfo() -> SourceInfo2 {
        SourceInfo2(
            sourceId: key,
            iconUrl: imageUrl,
            name: name,
            languages: languages,
            version: version,
            contentRating: contentRating
        )
    }

    func getModifiedImageRequest(url: URL, context: PageContext?) async -> URLRequest {
        var result: URLRequest
        do {
            result = try await getImageRequest(url: url.absoluteString, context: context)
        } catch {
            result = .init(url: url)
        }
        return await Self.modify(url: url, request: result)
    }

    static func modify(url: URL, request: URLRequest) async -> URLRequest {
        var request = request
        // add user-agent and stored cookies if not provided (for cloudflare)
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(
                await UserAgentProvider.shared.getUserAgent(),
                forHTTPHeaderField: "User-Agent"
            )
        }
        let cookies = HTTPCookie.requestHeaderFields(with: HTTPCookieStorage.shared.cookies(for: url) ?? [])
        for (key, value) in cookies {
            if key == "Cookie" {
                var cookieString = value
                // keep cookies in original request
                if let oldCookie = request.value(forHTTPHeaderField: "Cookie") {
                    cookieString += "; " + oldCookie
                }
                request.setValue(cookieString, forHTTPHeaderField: "Cookie")
            } else {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        return request
    }
}

extension AidokuRunner.Manga {
    func toOld() -> Manga {
        Manga(
            sourceId: sourceKey,
            id: key,
            title: title,
            author: authors?.joined(separator: ", "),
            artist: artists?.joined(separator: ", "),
            description: description,
            tags: tags,
            coverUrl: cover.flatMap({ URL(string: $0) }),
            url: url,
            status: {
                switch status {
                    case .unknown: .unknown
                    case .ongoing: .ongoing
                    case .completed: .completed
                    case .cancelled: .cancelled
                    case .hiatus: .hiatus
                }
            }(),
            nsfw: {
                switch contentRating {
                    case .unknown: .safe
                    case .safe: .safe
                    case .suggestive: .suggestive
                    case .nsfw: .nsfw
                }
            }(),
            viewer: {
                switch viewer {
                    case .unknown: .defaultViewer
                    case .rightToLeft: .rtl
                    case .leftToRight: .ltr
                    case .vertical: .vertical
                    case .webtoon: .scroll
                }
            }(),
            updateStrategy: updateStrategy,
            nextUpdateTime: nextUpdateTime.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) },
        )
    }

    func isLocal() -> Bool {
        sourceKey == LocalSourceRunner.sourceKey
    }
}

extension AidokuRunner.MangaStatus {
    var title: String {
        switch self {
            case .unknown: NSLocalizedString("UNKNOWN")
            case .ongoing: NSLocalizedString("ONGOING")
            case .completed: NSLocalizedString("COMPLETED")
            case .cancelled: NSLocalizedString("CANCELLED")
            case .hiatus: NSLocalizedString("HIATUS")
        }
    }
}

extension AidokuRunner.MangaContentRating {
    var title: String {
        switch self {
            case .unknown: NSLocalizedString("UNKNOWN")
            case .safe: NSLocalizedString("SAFE")
            case .suggestive: NSLocalizedString("SUGGESTIVE")
            case .nsfw: NSLocalizedString("NSFW")
        }
    }
}

extension AidokuRunner.Chapter {
    func formattedTitle() -> String {
        if volumeNumber == nil && (title?.isEmpty ?? true) {
            // Chapter X
            return if let chapterNumber {
                String(format: NSLocalizedString("CHAPTER_X"), chapterNumber)
            } else {
                NSLocalizedString("UNTITLED")
            }
        } else if let volumeNumber, chapterNumber == nil && title == nil {
            return String(format: NSLocalizedString("VOLUME_X"), volumeNumber)
        } else {
            var components: [String] = []
            // Vol.X
            if let volumeNumber {
                components.append(
                    String(format: NSLocalizedString("VOL_X"), volumeNumber)
                )
            }
            // Ch.X
            if let chapterNumber {
                components.append(
                    String(format: NSLocalizedString("CH_X"), chapterNumber)
                )
            }
            // title
            if let title, !title.isEmpty {
                if !components.isEmpty {
                    components.append("-")
                }
                components.append(title)
            }
            return components.joined(separator: " ")
        }
    }

    func formattedSubtitle(page: Int?, sourceKey: String) -> String? {
        var components: [String] = []
        // date
        if let dateUploaded {
            components.append(DateFormatter.localizedString(from: dateUploaded, dateStyle: .medium, timeStyle: .none))
        }
        // page (if reading in progress)
        if let page, page > 0 {
            components.append(String(format: NSLocalizedString("PAGE_X"), page))
        }
        // scanlator
        if let scanlators, !scanlators.isEmpty {
            components.append(scanlators.joined(separator: ", "))
        }
        // language (if source has multiple enabled)
        if
            let language,
            let languageCount = UserDefaults.standard.array(forKey: "\(sourceKey).languages")?.count,
            languageCount > 1
        {
            components.append(language)
        }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }

    func toOld(
        sourceId: String,
        mangaId: String,
        sourceOrder: Int? = nil
    ) -> Chapter {
        Chapter(
            sourceId: sourceId,
            id: key,
            mangaId: mangaId,
            title: title,
            scanlator: scanlators?.joined(separator: ", "),
            url: url?.absoluteString,
            lang: language ?? "en",
            chapterNum: chapterNumber,
            volumeNum: volumeNumber,
            dateUploaded: dateUploaded,
            thumbnail: thumbnail,
            locked: locked,
            sourceOrder: sourceOrder ?? 0
        )
    }
}

extension AidokuRunner.Page {
    func toOld(sourceId: String, chapterId: String) -> Page {
        switch content {
            case let .url(url, context):
                Page(
                    sourceId: sourceId,
                    chapterId: chapterId,
                    imageURL: url.absoluteString,
                    context: context,
                    hasDescription: hasDescription,
                    description: description
                )
            case let .text(text):
                Page(
                    sourceId: sourceId,
                    chapterId: chapterId,
                    text: text,
                    hasDescription: hasDescription,
                    description: description
                )
            case let .image(image):
                Page(
                    sourceId: sourceId,
                    chapterId: chapterId,
                    image: image.image,
                    hasDescription: hasDescription,
                    description: description
                )
            case let .zipFile(url, filePath):
                Page(
                    sourceId: sourceId,
                    chapterId: chapterId,
                    imageURL: filePath,
                    zipURL: url.absoluteString,
                    hasDescription: hasDescription,
                    description: description
                )
        }
    }
}

extension AidokuRunner.SelectFilter {
    var resolvedDefaultValue: String {
        defaultValue ?? ids?.first ?? options.first ?? ""
    }
}

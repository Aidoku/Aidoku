//
//  WasmAidoku.swift
//  Aidoku
//
//  Created by Skitty on 3/29/22.
//

import Foundation

class WasmAidoku: WasmImports {

    var globalStore: WasmGlobalStore

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "aidoku") {
        try? globalStore.vm.linkFunction(name: "create_manga", namespace: namespace, function: self.create_manga)
        try? globalStore.vm.linkFunction(name: "create_manga_result", namespace: namespace, function: self.create_manga_result)
        try? globalStore.vm.linkFunction(name: "create_chapter", namespace: namespace, function: self.create_chapter)
        try? globalStore.vm.linkFunction(name: "create_page", namespace: namespace, function: self.create_page)
        try? globalStore.vm.linkFunction(name: "create_deeplink", namespace: namespace, function: self.create_deeplink)
    }
}

// MARK: - Aidoku Objects
extension WasmAidoku {

    var create_manga: (
        Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32,
        Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32
    ) -> Int32 {
        // swiftlint:disable:next line_length
        { id, idLen, coverUrl, coverUrlLen, title, titleLen, author, authorLen, artist, artistLen, description, descriptionLen, url, urlLen, tags, tagStrLens, tagCount, status, nsfw, viewer in
            guard idLen > 0 else { return -1 }
            if let mangaId = self.globalStore.readString(offset: id, length: idLen) {
                var tagList: [String] = []
                let tagStrings: [Int32] = self.globalStore.readValues(offset: tags, length: tagCount) ?? []
                let tagStringLengths: [Int32] = self.globalStore.readValues(offset: tagStrLens, length: tagCount) ?? []
                for i in 0..<Int(tagCount) {
                    if let str = self.globalStore.readString(offset: tagStrings[i], length: tagStringLengths[i]) {
                        tagList.append(str)
                    }
                }
                let coverString = coverUrlLen > 0 ? self.globalStore.readString(offset: coverUrl, length: coverUrlLen) : nil
                let coverUrl: URL?
                if let coverString = coverString {
                    coverUrl = URL(string: coverString)
                } else {
                    coverUrl = nil
                }
                let urlString = urlLen > 0 ? self.globalStore.readString(offset: url, length: urlLen) : nil
                let url: URL?
                if let urlString = urlString {
                    url = URL(string: urlString)
                } else {
                    url = nil
                }
                let manga = Manga(
                    sourceId: self.globalStore.id,
                    id: mangaId,
                    title: titleLen > 0 ? self.globalStore.readString(offset: title, length: titleLen) : nil,
                    author: authorLen > 0 ? self.globalStore.readString(offset: author, length: authorLen) : nil,
                    artist: artistLen > 0 ? self.globalStore.readString(offset: artist, length: artistLen) : nil,
                    description: descriptionLen > 0 ? self.globalStore.readString(
                        offset: description,
                        length: descriptionLen
                    ) : nil,
                    tags: tagList,
                    coverUrl: coverUrl,
                    url: url,
                    status: PublishingStatus(rawValue: Int(status)) ?? .unknown,
                    nsfw: MangaContentRating(rawValue: Int(nsfw)) ?? .safe,
                    viewer: MangaViewer(rawValue: Int(viewer)) ?? .defaultViewer
                )
                return self.globalStore.storeStdValue(manga)
            }
            return -1
        }
    }

    var create_manga_result: (Int32, Int32) -> Int32 {
        { mangaArray, hasMore in
            if let manga = self.globalStore.readStdValue(mangaArray) as? [Manga] {
                return self.globalStore.storeStdValue(MangaPageResult(manga: manga, hasNextPage: hasMore != 0))
            }
            return -1
        }
    }

    var create_chapter: (Int32, Int32, Int32, Int32, Float32, Float32, Float64, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { id, idLen, name, nameLen, volume, chapter, dateUploaded, scanlator, scanlatorLen, url, urlLen, lang, langLen in
            if let chapterId = self.globalStore.readString(offset: id, length: idLen) {
                let chapter = Chapter(
                    sourceId: self.globalStore.id,
                    id: chapterId,
                    mangaId: self.globalStore.currentManga,
                    title: nameLen > 0 ? self.globalStore.readString(offset: name, length: nameLen) : nil,
                    scanlator: scanlatorLen > 0 ? self.globalStore.readString(offset: scanlator, length: scanlatorLen) : nil,
                    url: urlLen > 0 ? self.globalStore.readString(offset: url, length: urlLen) : nil,
                    lang: langLen > 0 ? self.globalStore.readString(offset: lang, length: langLen) ?? "en" : "en",
                    chapterNum: chapter >= 0 ? Float(chapter) : nil,
                    volumeNum: volume >= 0 ? Float(volume) : nil,
                    dateUploaded: dateUploaded > 0 ? Date(timeIntervalSince1970: TimeInterval(dateUploaded)) : nil,
                    sourceOrder: self.globalStore.chapterCounter
                )
                self.globalStore.chapterCounter += 1
                return self.globalStore.storeStdValue(chapter)
            }
            return -1
        }
    }

    var create_page: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { index, imageUrl, imageUrlLength, base64, base64Length, text, textLength in
            self.globalStore.storeStdValue(Page(
                sourceId: self.globalStore.id,
                chapterId: "",
                index: Int(index),
                imageURL: imageUrlLength > 0 ? self.globalStore.readString(offset: imageUrl, length: imageUrlLength) : nil,
                base64: base64Length > 0 ? self.globalStore.readString(offset: base64, length: base64Length) : nil,
                text: textLength > 0 ? self.globalStore.readString(offset: text, length: textLength) : nil
            ))
        }
    }

    var create_deeplink: (Int32, Int32) -> Int32 {
        { manga, chapter in
            self.globalStore.storeStdValue(DeepLink(
                manga: manga > 0 ? self.globalStore.readStdValue(manga) as? Manga : nil,
                chapter: chapter > 0 ? self.globalStore.readStdValue(chapter) as? Chapter : nil
            ))
        }
    }
}

//
//  WasmAidoku.swift
//  Aidoku
//
//  Created by Skitty on 3/29/22.
//

import Foundation
import WasmInterpreter

class WasmAidoku: WasmModule {

    var globalStore: WasmGlobalStore

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "aidoku") {
        try? globalStore.vm.addImportHandler(named: "create_manga", namespace: namespace, block: self.create_manga)
        try? globalStore.vm.addImportHandler(named: "create_manga_result", namespace: namespace, block: self.create_manga_result)
        try? globalStore.vm.addImportHandler(named: "create_chapter", namespace: namespace, block: self.create_chapter)
        try? globalStore.vm.addImportHandler(named: "create_page", namespace: namespace, block: self.create_page)

//        try? vm.addImportHandler(named: "setting_get_string", namespace: "env", block: self.setting_get_string)
//        try? vm.addImportHandler(named: "setting_get_int", namespace: "env", block: self.setting_get_int)
//        try? vm.addImportHandler(named: "setting_get_float", namespace: "env", block: self.setting_get_float)
//        try? vm.addImportHandler(named: "setting_get_bool", namespace: "env", block: self.setting_get_bool)
//        try? vm.addImportHandler(named: "setting_get_array", namespace: "env", block: self.setting_get_array)
    }
}

// MARK: - Aidoku Objects
extension WasmAidoku {

    var create_manga: (
        Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32,
        Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32
    ) -> Int32 {
        // swiftlint:disable:next line_length
        { id, id_len, cover_url, cover_url_len, title, title_len, author, author_len, _, _, description, description_len, url, url_len, tags, tag_str_lens, tag_count, status, nsfw, viewer in
            guard id_len > 0 else { return -1 }
            if let mangaId = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                var tagList: [String] = []
                let tagStrings: [Int32] = (try? self.globalStore.vm.valuesFromHeap(byteOffset: Int(tags), length: Int(tag_count))) ?? []
                let tagStringLengths: [Int32] = (try? self.globalStore.vm.valuesFromHeap(
                    byteOffset: Int(tag_str_lens),
                    length: Int(tag_count)
                )) ?? []
                for i in 0..<Int(tag_count) {
                    if let str = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(tagStrings[i]), length: Int(tagStringLengths[i])) {
                        tagList.append(str)
                    }
                }
                let manga = Manga(
                    sourceId: self.globalStore.id,
                    id: mangaId,
                    title: title_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(title), length: Int(title_len)) : nil,
                    author: author_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(author), length: Int(author_len)) : nil,
                    description: description_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(description),
                                                                                               length: Int(description_len)) : nil,
                    tags: tagList,
                    cover: cover_url_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(cover_url),
                                                                                       length: Int(cover_url_len)) : nil,
                    url: url_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(url), length: Int(url_len)) : nil,
                    status: MangaStatus(rawValue: Int(status)) ?? .unknown,
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
                let result = self.globalStore.storeStdValue(MangaPageResult(manga: manga, hasNextPage: hasMore != 0))
                self.globalStore.addStdReference(to: result, target: mangaArray)
                return result
            }
            return -1
        }
    }

    var create_chapter: (Int32, Int32, Int32, Int32, Float32, Float32, Float64, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { id, id_len, name, name_len, volume, chapter, dateUploaded, scanlator, scanlator_len, _, _, lang, lang_len in
            if let chapterId = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                let chapter = Chapter(
                    sourceId: self.globalStore.id,
                    id: chapterId,
                    mangaId: self.globalStore.currentManga,
                    title: name_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) : nil,
                    scanlator: scanlator_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(scanlator),
                                                                                           length: Int(scanlator_len)) : nil,
                    lang: lang_len > 0 ? (try? self.globalStore.vm.stringFromHeap(byteOffset: Int(lang),
                                                                                  length: Int(lang_len))) ?? "en" : "en",
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
            let page = Page(
                index: Int(index),
                imageURL: imageUrlLength > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(imageUrl),
                                                                                       length: Int(imageUrlLength)) : nil,
                base64: base64Length > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(base64),
                                                                                   length: Int(base64Length)) : nil,
                text: textLength > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(text),
                                                                               length: Int(textLength)) : nil
            )
            return self.globalStore.storeStdValue(page)
        }
    }
}

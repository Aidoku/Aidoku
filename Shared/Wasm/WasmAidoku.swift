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
    let sourceId: String

    var descriptorPointer = -1
    var descriptors: [Any] = []

    var chapterCounter = 0
    var currentManga = ""

    let defaultLocale = "en_US_POSIX"
    let defaultTimeZone = "UTC"

    init(globalStore: WasmGlobalStore, sourceId: String) {
        self.globalStore = globalStore
        self.sourceId = sourceId
    }

    func export(into namespace: String = "aidoku") {
        try? globalStore.vm.addImportHandler(named: "filter", namespace: namespace, block: self.create_filter)
        try? globalStore.vm.addImportHandler(named: "listing", namespace: namespace, block: self.create_listing)
        try? globalStore.vm.addImportHandler(named: "manga", namespace: namespace, block: self.create_manga)
        try? globalStore.vm.addImportHandler(named: "chapter", namespace: namespace, block: self.create_chapter)
        try? globalStore.vm.addImportHandler(named: "page", namespace: namespace, block: self.create_page)

//        try? vm.addImportHandler(named: "setting_get_string", namespace: "env", block: self.setting_get_string)
//        try? vm.addImportHandler(named: "setting_get_int", namespace: "env", block: self.setting_get_int)
//        try? vm.addImportHandler(named: "setting_get_float", namespace: "env", block: self.setting_get_float)
//        try? vm.addImportHandler(named: "setting_get_bool", namespace: "env", block: self.setting_get_bool)
//        try? vm.addImportHandler(named: "setting_get_array", namespace: "env", block: self.setting_get_array)
    }
}

// MARK: - Aidoku Objects
extension WasmAidoku {

    var create_filter: (Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { type, name, name_len, value, default_value in
            let filter: Filter
            let name = (try? self.globalStore.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len))) ?? ""
            if type == FilterType.note.rawValue {
                filter = Filter(text: name)
            } else if type == FilterType.text.rawValue {
                filter = Filter(name: name)
            } else if type == FilterType.check.rawValue || type == FilterType.genre.rawValue {
                filter = Filter(
                    type: FilterType(rawValue: Int(type)) ?? .check,
                    name: name,
                    canExclude: value > 0,
                    default: Int(default_value)
                )
            } else if type == FilterType.select.rawValue {
                filter = Filter(
                    name: name,
                    options: value > 0 ? self.descriptors[Int(value)] as? [String] ?? [] : [],
                    default: Int(default_value)
                )
            } else if type == FilterType.sort.rawValue {
                let options = self.descriptors[Int(value)] as? [Filter] ?? []
                filter = Filter(
                    name: name,
                    options: options,
                    value: value > 0 ? (self.descriptors[Int(value)] as? Filter)?.value as? SortOption : nil,
                    default: default_value > 0 ? (self.descriptors[Int(default_value)] as? Filter)?.value as? SortOption : nil
                )
            } else if type == FilterType.sortOption.rawValue {
                filter = Filter(
                    name: name,
                    canReverse: value > 0
                )
            } else if type == FilterType.group.rawValue {
                filter = Filter(
                    name: name,
                    filters: value > 0 ? self.descriptors[Int(value)] as? [Filter] ?? [] : []
                )
            } else {
                filter = Filter(
                    type: FilterType(rawValue: Int(type)) ?? .text,
                    name: name
                )
            }
            self.descriptorPointer += 1
            self.descriptors.append(filter)
            return Int32(self.descriptorPointer)
        }
    }

    var create_listing: (Int32, Int32, Int32) -> Int32 {
        { name, name_len, flags in
            if let str = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) {
                self.descriptorPointer += 1
                self.descriptors.append(Listing(name: str, flags: flags))
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }

    var create_manga: (
        Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32,
        Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32
    ) -> Int32 {
        // swiftlint:disable:next line_length
        { id, id_len, cover_url, cover_url_len, title, title_len, author, author_len, _, _, description, description_len, status, tags, tag_str_lens, tag_count, url, url_len, nsfw, viewer in
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
                    sourceId: self.sourceId,
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
                self.descriptorPointer += 1
                self.descriptors.append(manga)
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }

    var create_chapter: (Int32, Int32, Int32, Int32, Float32, Float32, Int64, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { id, id_len, name, name_len, volume, chapter, dateUploaded, scanlator, scanlator_len, _, _, lang, lang_len in
            if let chapterId = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(id), length: Int(id_len)) {
                self.descriptorPointer += 1
                self.descriptors.append(
                    Chapter(
                        sourceId: self.sourceId,
                        id: chapterId,
                        mangaId: self.currentManga,
                        title: name_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(name), length: Int(name_len)) : nil,
                        scanlator: scanlator_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(scanlator),
                                                                                               length: Int(scanlator_len)) : nil,
                        lang: lang_len > 0 ? (try? self.globalStore.vm.stringFromHeap(byteOffset: Int(lang),
                                                                                      length: Int(lang_len))) ?? "en" : "en",
                        chapterNum: chapter >= 0 ? Float(chapter) : nil,
                        volumeNum: volume >= 0 ? Float(volume) : nil,
                        dateUploaded: dateUploaded > 0 ? Date(timeIntervalSince1970: TimeInterval(dateUploaded)) : nil,
                        sourceOrder: self.chapterCounter
                    )
                )
                self.chapterCounter += 1
                return Int32(self.descriptorPointer)
            }
            return -1
        }
    }

    var create_page: (Int32, Int32, Int32, Int32, Int32, Int32, Int32) -> Int32 {
        { index, image_url, image_url_len, _, _, _, _ in
            self.descriptorPointer += 1
            self.descriptors.append(
                Page(
                    index: Int(index),
                    imageURL: image_url_len > 0 ? try? self.globalStore.vm.stringFromHeap(byteOffset: Int(image_url),
                                                                                          length: Int(image_url_len)) : nil
                )
            )
            return Int32(self.descriptorPointer)
        }
    }
}

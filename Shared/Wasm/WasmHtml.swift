//
//  WasmHtml.swift
//  Aidoku
//
//  Created by Skitty on 2/4/22.
//

import Foundation
import WasmInterpreter
import SwiftSoup

class WasmHtml {

    var globalStore: WasmGlobalStore

    var descriptorPointer: Int32 = -1
    var descriptors: [Int32: Any] = [:]
    var references: [Int32: [Int32]] = [:]

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "html") {
        try? globalStore.vm.addImportHandler(named: "scraper_parse", namespace: namespace, block: self.scraper_parse)
        try? globalStore.vm.addImportHandler(named: "scraper_select", namespace: namespace, block: self.scraper_select)
        try? globalStore.vm.addImportHandler(named: "scraper_attr", namespace: namespace, block: self.scraper_attr)
        try? globalStore.vm.addImportHandler(named: "scraper_text", namespace: namespace, block: self.scraper_text)

        try? globalStore.vm.addImportHandler(named: "scraper_array_size", namespace: namespace, block: self.scraper_array_size)
        try? globalStore.vm.addImportHandler(named: "scraper_array_get", namespace: namespace, block: self.scraper_array_get)

        try? globalStore.vm.addImportHandler(named: "scraper_free", namespace: namespace, block: self.scraper_free)
    }

    func readValue(_ descriptor: Int32) -> Any? {
        descriptors[descriptor]
    }

    func storeValue(_ data: Any, from: Int32? = nil) -> Int32 {
        descriptorPointer += 1
        descriptors[descriptorPointer] = data
        if let d = from {
            var refs = references[d] ?? []
            refs.append(descriptorPointer)
            references[d] = refs
        }
        return descriptorPointer
    }

    func removeValue(_ descriptor: Int32) {
        descriptors.removeValue(forKey: descriptor)
        for d in references[descriptor] ?? [] {
            removeValue(d)
        }
        references.removeValue(forKey: descriptor)
    }
}

extension WasmHtml {

    var scraper_parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let readData = try? self.globalStore.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
               let content = String(bytes: readData, encoding: .utf8),
               let obj = try? SwiftSoup.parse(content) {
                return self.storeValue(obj)
            }
            return -1
        }
    }

    var scraper_free: (Int32) -> Void {
        { descriptor in
            self.removeValue(descriptor)
        }
    }

    var scraper_select: (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selector >= 0 else { return -1 }
            if let selectorString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(selector), length: Int(selectorLength)) {
                if let object = try? (self.readValue(descriptor) as? SwiftSoup.Element)?.select(selectorString) {
                    return self.storeValue(object, from: descriptor)
                } else if let object = try? (self.readValue(descriptor) as? SwiftSoup.Elements)?.select(selectorString) {
                    return self.storeValue(object, from: descriptor)
                }
            }
            return -1
        }
    }

    var scraper_attr: (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selector >= 0 else { return -1 }
            if let selectorString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(selector), length: Int(selectorLength)) {
                if let object = try? (self.readValue(descriptor) as? SwiftSoup.Elements)?.attr(selectorString) {
                   return self.storeValue(object, from: descriptor)
                } else if let object = try? (self.readValue(descriptor) as? SwiftSoup.Element)?.attr(selectorString) {
                    return self.storeValue(object, from: descriptor)
                 }
            }
            return -1
        }
    }

    var scraper_text: (Int32, Int32) -> Void {
        { descriptor, buffer in
            guard descriptor >= 0 else { return }
            var finalString: String?
            if let string = try? (self.readValue(descriptor) as? SwiftSoup.Elements)?.text() {
                finalString = string
            } else if let string = try? (self.readValue(descriptor) as? SwiftSoup.Element)?.text() {
                finalString = string
            } else if let string = self.readValue(descriptor) as? String {
                finalString = string
            }
            if let string = finalString {
                try? self.globalStore.vm.writeToHeap(string: string, byteOffset: Int(buffer))
            }
        }
    }

    var scraper_array_size: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            if let array = (self.readValue(descriptor) as? SwiftSoup.Elements)?.array() {
                return Int32(array.count)
            }
            return 0
        }
    }

    var scraper_array_get: (Int32, Int32) -> Int32 {
        { descriptor, index in
            guard descriptor >= 0 else { return -1 }
            if let array = (self.readValue(descriptor) as? SwiftSoup.Elements)?.array() {
                if index >= array.count { return -1 }
                return self.storeValue(array[Int(index)], from: descriptor)
            }
            return -1
        }
    }
}

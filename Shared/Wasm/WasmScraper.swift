//
//  WasmScraper.swift
//  Aidoku
//
//  Created by Skitty on 2/4/22.
//

import Foundation
import WasmInterpreter
import SwiftSoup

class WasmScraper {

    let vm: WasmInterpreter
    let memory: WasmMemory

    var descriptorPointer: Int32 = -1
    var descriptors: [Int32: Any] = [:]
    var references: [Int32: [Int32]] = [:]

    init(vm: WasmInterpreter, memory: WasmMemory) {
        self.vm = vm
        self.memory = memory
    }

    func export() {
        try? vm.addImportHandler(named: "scraper_parse", namespace: "env", block: self.scraper_parse)
        try? vm.addImportHandler(named: "scraper_select", namespace: "env", block: self.scraper_select)
        try? vm.addImportHandler(named: "scraper_attr", namespace: "env", block: self.scraper_attr)
        try? vm.addImportHandler(named: "scraper_text", namespace: "env", block: self.scraper_text)

        try? vm.addImportHandler(named: "scraper_array_size", namespace: "env", block: self.scraper_array_size)
        try? vm.addImportHandler(named: "scraper_array_get", namespace: "env", block: self.scraper_array_get)

        try? vm.addImportHandler(named: "scraper_free", namespace: "env", block: self.scraper_free)
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

    var scraper_parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let readData = try? self.vm.dataFromHeap(byteOffset: Int(data), length: Int(size)),
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
            if let selectorString = try? self.vm.stringFromHeap(byteOffset: Int(selector), length: Int(selectorLength)) {
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
            if let selectorString = try? self.vm.stringFromHeap(byteOffset: Int(selector), length: Int(selectorLength)) {
                if let object = try? (self.readValue(descriptor) as? SwiftSoup.Elements)?.attr(selectorString) {
                   return self.storeValue(object, from: descriptor)
                } else if let object = try? (self.readValue(descriptor) as? SwiftSoup.Element)?.attr(selectorString) {
                    return self.storeValue(object, from: descriptor)
                 }
            }
            return -1
        }
    }

    var scraper_text: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return 0 }
            if let string = try? (self.readValue(descriptor) as? SwiftSoup.Elements)?.text() {
                return self.vm.write(string: string, memory: self.memory)
            } else if let string = try? (self.readValue(descriptor) as? SwiftSoup.Element)?.text() {
                return self.vm.write(string: string, memory: self.memory)
            } else if let string = self.readValue(descriptor) as? String {
                return self.vm.write(string: string, memory: self.memory)
            }
            return 0
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

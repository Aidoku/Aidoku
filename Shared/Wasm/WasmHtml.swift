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

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "html") {
        try? globalStore.vm.addImportHandler(named: "parse", namespace: namespace, block: self.parse)
        try? globalStore.vm.addImportHandler(named: "parse_fragment", namespace: namespace, block: self.parseFragment)
        try? globalStore.vm.addImportHandler(named: "close", namespace: namespace, block: self.free)

        try? globalStore.vm.addImportHandler(named: "select", namespace: namespace, block: self.select)
        try? globalStore.vm.addImportHandler(named: "first", namespace: namespace, block: self.first)
        try? globalStore.vm.addImportHandler(named: "body", namespace: namespace, block: self.select)
        try? globalStore.vm.addImportHandler(named: "text", namespace: namespace, block: self.text)
        try? globalStore.vm.addImportHandler(named: "attr", namespace: namespace, block: self.attr)
        try? globalStore.vm.addImportHandler(named: "html", namespace: namespace, block: self.html)
        try? globalStore.vm.addImportHandler(named: "outer_html", namespace: namespace, block: self.outerHtml)

        try? globalStore.vm.addImportHandler(named: "id", namespace: namespace, block: self.id)
        try? globalStore.vm.addImportHandler(named: "tag_name", namespace: namespace, block: self.tagName)
        try? globalStore.vm.addImportHandler(named: "class_name", namespace: namespace, block: self.className)
        try? globalStore.vm.addImportHandler(named: "has_class", namespace: namespace, block: self.hasClass)
    }
}

extension WasmHtml {

    var parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let content = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(data), length: Int(size)),
               let obj = try? SwiftSoup.parse(content) {
                return self.globalStore.storeStdValue(obj)
            }
            return -1
        }
    }

    var parseFragment: (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let content = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(data), length: Int(size)),
               let obj = try? SwiftSoup.parseBodyFragment(content) {
                return self.globalStore.storeStdValue(obj)
            }
            return -1
        }
    }

    var free: (Int32) -> Void {
        { descriptor in
            self.globalStore.removeStdValue(descriptor)
        }
    }

    var select: (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selector >= 0 else { return -1 }
            if let selectorString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(selector), length: Int(selectorLength)) {
                if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.select(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                } else if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.select(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                }
            }
            return -1
        }
    }

    var first: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.first() {
                return self.globalStore.storeStdValue(element, from: descriptor)
            }
            return -1
        }
    }

    var body: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Document)?.body() {
                return self.globalStore.storeStdValue(element, from: descriptor)
            }
            return -1
        }
    }

    var text: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.text() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var attr: (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selectorLength > 0 else { return -1 }
            if let selectorString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(selector), length: Int(selectorLength)) {
                if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.attr(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                } else if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.attr(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                 }
            }
            return -1
        }
    }

    var html: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.html() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.html() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var outerHtml: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.outerHtml() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.outerHtml() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }
}

extension WasmHtml {

    var id: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.id() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var tagName: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.tagName() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var className: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.className() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var hasClass: (Int32, Int32, Int32) -> Int32 {
        { descriptor, className, classLength in
            guard descriptor >= 0 else { return 0 }
            if let classString = try? self.globalStore.vm.stringFromHeap(byteOffset: Int(className), length: Int(classLength)) {
                if (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.hasClass(classString) ?? false {
                    return 1
                }
            }
            return 0
        }
    }
}

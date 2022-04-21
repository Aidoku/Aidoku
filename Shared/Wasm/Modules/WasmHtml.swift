//
//  WasmHtml.swift
//  Aidoku
//
//  Created by Skitty on 2/4/22.
//

import Foundation
import SwiftSoup

class WasmHtml {

    var globalStore: WasmGlobalStore

    init(globalStore: WasmGlobalStore) {
        self.globalStore = globalStore
    }

    func export(into namespace: String = "html") {
        globalStore.export(named: "parse", namespace: namespace, block: self.parse)
        globalStore.export(named: "parse_fragment", namespace: namespace, block: self.parseFragment)

        globalStore.export(named: "select", namespace: namespace, block: self.select)
        globalStore.export(named: "attr", namespace: namespace, block: self.attr)

        globalStore.export(named: "first", namespace: namespace, block: self.first)
        globalStore.export(named: "last", namespace: namespace, block: self.first)
        globalStore.export(named: "array", namespace: namespace, block: self.array)

        globalStore.export(named: "base_uri", namespace: namespace, block: self.baseUri)
        globalStore.export(named: "body", namespace: namespace, block: self.select)
        globalStore.export(named: "text", namespace: namespace, block: self.text)
        globalStore.export(named: "html", namespace: namespace, block: self.html)
        globalStore.export(named: "outer_html", namespace: namespace, block: self.outerHtml)

        globalStore.export(named: "id", namespace: namespace, block: self.id)
        globalStore.export(named: "tag_name", namespace: namespace, block: self.tagName)
        globalStore.export(named: "class_name", namespace: namespace, block: self.className)
        globalStore.export(named: "has_class", namespace: namespace, block: self.hasClass)
        globalStore.export(named: "has_attr", namespace: namespace, block: self.hasAttr)
    }
}

extension WasmHtml {

    var parse: @convention(block) (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let content = self.globalStore.readString(offset: data, length: size),
               let obj = try? SwiftSoup.parse(content) {
                return self.globalStore.storeStdValue(obj)
            }
            return -1
        }
    }

    var parseFragment: @convention(block) (Int32, Int32) -> Int32 {
        { data, size in
            guard data > 0, size > 0 else { return -1 }
            if let content = self.globalStore.readString(offset: data, length: size),
               let obj = try? SwiftSoup.parseBodyFragment(content) {
                return self.globalStore.storeStdValue(obj)
            }
            return -1
        }
    }

    var select: @convention(block) (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selector >= 0 else { return -1 }
            if let selectorString = self.globalStore.readString(offset: selector, length: selectorLength) {
                if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.select(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                } else if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.select(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                }
            }
            return -1
        }
    }

    var first: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.first() {
                return self.globalStore.storeStdValue(element, from: descriptor)
            }
            return -1
        }
    }

    var last: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.last() {
                return self.globalStore.storeStdValue(element, from: descriptor)
            }
            return -1
        }
    }

    var baseUri: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let uri = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Node)?.getBaseUri() {
                return self.globalStore.storeStdValue(uri, from: descriptor)
            }
            return -1
        }
    }

    var body: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Document)?.body() {
                return self.globalStore.storeStdValue(element, from: descriptor)
            }
            return -1
        }
    }

    var text: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.text() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var array: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let array = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.array() {
                return self.globalStore.storeStdValue(array, from: descriptor)
            }
            return -1
        }
    }

    var attr: @convention(block) (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selectorLength > 0 else { return -1 }
            if let selectorString = self.globalStore.readString(offset: selector, length: selectorLength) {
                if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.attr(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                } else if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.attr(selectorString) {
                    return self.globalStore.storeStdValue(object, from: descriptor)
                 }
            }
            return -1
        }
    }

    var html: @convention(block) (Int32) -> Int32 {
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

    var outerHtml: @convention(block) (Int32) -> Int32 {
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

    var id: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.id() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var tagName: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.tagName() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var className: @convention(block) (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.className() {
                return self.globalStore.storeStdValue(string, from: descriptor)
            }
            return -1
        }
    }

    var hasClass: @convention(block) (Int32, Int32, Int32) -> Int32 {
        { descriptor, className, classLength in
            guard descriptor >= 0 else { return 0 }
            if let classString = self.globalStore.readString(offset: className, length: classLength) {
                if (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.hasClass(classString) ?? false {
                    return 1
                }
            }
            return 0
        }
    }

    var hasAttr: @convention(block) (Int32, Int32, Int32) -> Int32 {
        { descriptor, attrName, attrLength in
            guard descriptor >= 0 else { return 0 }
            if let key = self.globalStore.readString(offset: attrName, length: attrLength) {
                if (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.hasAttr(key) ?? false {
                    return 1
                }
            }
            return 0
        }
    }
}

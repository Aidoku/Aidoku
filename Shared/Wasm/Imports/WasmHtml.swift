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
        try? globalStore.vm.linkFunction(name: "parse", namespace: namespace, function: self.parse)
        try? globalStore.vm.linkFunction(name: "parse_fragment", namespace: namespace, function: self.parseFragment)
        try? globalStore.vm.linkFunction(name: "parse_with_uri", namespace: namespace, function: self.parseWithUri)
        try? globalStore.vm.linkFunction(name: "parse_fragment_with_uri", namespace: namespace, function: self.parseFragmentWithUri)

        try? globalStore.vm.linkFunction(name: "select", namespace: namespace, function: self.select)
        try? globalStore.vm.linkFunction(name: "attr", namespace: namespace, function: self.attr)

        try? globalStore.vm.linkFunction(name: "set_text", namespace: namespace, function: self.setText)
        try? globalStore.vm.linkFunction(name: "set_html", namespace: namespace, function: self.setHtml)
        try? globalStore.vm.linkFunction(name: "prepend", namespace: namespace, function: self.prepend)
        try? globalStore.vm.linkFunction(name: "append", namespace: namespace, function: self.append)

        try? globalStore.vm.linkFunction(name: "first", namespace: namespace, function: self.first)
        try? globalStore.vm.linkFunction(name: "last", namespace: namespace, function: self.last)
        try? globalStore.vm.linkFunction(name: "next", namespace: namespace, function: self.next)
        try? globalStore.vm.linkFunction(name: "previous", namespace: namespace, function: self.previous)

        try? globalStore.vm.linkFunction(name: "base_uri", namespace: namespace, function: self.baseUri)
        try? globalStore.vm.linkFunction(name: "body", namespace: namespace, function: self.body)
        try? globalStore.vm.linkFunction(name: "text", namespace: namespace, function: self.text)
        try? globalStore.vm.linkFunction(name: "untrimmed_text", namespace: namespace, function: self.untrimmedText)
        try? globalStore.vm.linkFunction(name: "own_text", namespace: namespace, function: self.ownText)
        try? globalStore.vm.linkFunction(name: "data", namespace: namespace, function: self.data)
        try? globalStore.vm.linkFunction(name: "array", namespace: namespace, function: self.array)
        try? globalStore.vm.linkFunction(name: "html", namespace: namespace, function: self.html)
        try? globalStore.vm.linkFunction(name: "outer_html", namespace: namespace, function: self.outerHtml)

        try? globalStore.vm.linkFunction(name: "escape", namespace: namespace, function: self.escape)
        try? globalStore.vm.linkFunction(name: "unescape", namespace: namespace, function: self.unescape)

        try? globalStore.vm.linkFunction(name: "id", namespace: namespace, function: self.id)
        try? globalStore.vm.linkFunction(name: "tag_name", namespace: namespace, function: self.tagName)
        try? globalStore.vm.linkFunction(name: "class_name", namespace: namespace, function: self.className)
        try? globalStore.vm.linkFunction(name: "has_class", namespace: namespace, function: self.hasClass)
        try? globalStore.vm.linkFunction(name: "has_attr", namespace: namespace, function: self.hasAttr)
    }
}

extension WasmHtml {

    var parse: (Int32, Int32) -> Int32 {
        { data, size in
            guard size > 0 else { return -1 }
            if let content = self.globalStore.readString(offset: data, length: size),
               let obj = try? SwiftSoup.parse(content) {
                return self.globalStore.storeStdValue(obj)
            }
            return -1
        }
    }

    var parseFragment: (Int32, Int32) -> Int32 {
        { data, size in
            guard size > 0 else { return -1 }
            if let content = self.globalStore.readString(offset: data, length: size),
               let obj = try? SwiftSoup.parseBodyFragment(content) {
                return self.globalStore.storeStdValue(obj)
            }
            return -1
        }
    }

    var parseWithUri: (Int32, Int32, Int32, Int32) -> Int32 {
        { data, size, uri, uriLength in
            guard size > 0 else { return -1 }
            if let content = self.globalStore.readString(offset: data, length: size) {
                if uriLength > 0,
                   let baseUri = self.globalStore.readString(offset: uri, length: uriLength),
                   let obj = try? SwiftSoup.parse(content, baseUri) {
                    return self.globalStore.storeStdValue(obj)
                } else if let obj = try? SwiftSoup.parse(content) {
                    return self.globalStore.storeStdValue(obj)
                }
            }
            return -1
        }
    }

    var parseFragmentWithUri: (Int32, Int32, Int32, Int32) -> Int32 {
        { data, size, uri, uriLength in
            guard size > 0 else { return -1 }
            if let content = self.globalStore.readString(offset: data, length: size) {
                if uriLength > 0,
                   let baseUri = self.globalStore.readString(offset: uri, length: uriLength),
                   let obj = try? SwiftSoup.parseBodyFragment(content, baseUri) {
                    return self.globalStore.storeStdValue(obj)
                } else if let obj = try? SwiftSoup.parseBodyFragment(content) {
                    return self.globalStore.storeStdValue(obj)
                }
            }
            return -1
        }
    }

    var select: (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selector >= 0 else { return -1 }
            if let selectorString = self.globalStore.readString(offset: selector, length: selectorLength) {
                if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.select(selectorString) {
                    return self.globalStore.storeStdValue(object)
                } else if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.select(selectorString) {
                    return self.globalStore.storeStdValue(object)
                }
            }
            return -1
        }
    }

    var attr: (Int32, Int32, Int32) -> Int32 {
        { descriptor, selector, selectorLength in
            guard descriptor >= 0, selectorLength > 0 else { return -1 }
            if let selectorString = self.globalStore.readString(offset: selector, length: selectorLength) {
                if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.attr(selectorString) {
                    return self.globalStore.storeStdValue(object)
                } else if let object = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.attr(selectorString) {
                    return self.globalStore.storeStdValue(object)
                 }
            }
            return -1
        }
    }

    var setText: (Int32, Int32, Int32) -> Int32 {
        { descriptor, text, textLength in
            guard descriptor >= 0 else { return -1 }
            if let string = self.globalStore.readString(offset: text, length: textLength),
               (try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text(string)) != nil {
                return 0
            }
            return -1
        }
    }

    var setHtml: (Int32, Int32, Int32) -> Int32 {
        { descriptor, text, textLength in
            guard descriptor >= 0 else { return -1 }
            if let string = self.globalStore.readString(offset: text, length: textLength),
               (try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.html(string)) != nil {
                return 0
            }
            return -1
        }
    }

    var prepend: (Int32, Int32, Int32) -> Int32 {
        { descriptor, text, textLength in
            guard descriptor >= 0 else { return -1 }
            if let string = self.globalStore.readString(offset: text, length: textLength),
               (try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.prepend(string)) != nil {
                return 0
            }
            return -1
        }
    }

    var append: (Int32, Int32, Int32) -> Int32 {
        { descriptor, text, textLength in
            guard descriptor >= 0 else { return -1 }
            if let string = self.globalStore.readString(offset: text, length: textLength),
               (try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.append(string)) != nil {
                return 0
            }
            return -1
        }
    }

    var first: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.first() {
                return self.globalStore.storeStdValue(element)
            }
            return -1
        }
    }

    var last: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.last() {
                return self.globalStore.storeStdValue(element)
            }
            return -1
        }
    }

    var next: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.nextElementSibling() {
                return self.globalStore.storeStdValue(element)
            }
            return -1
        }
    }

    var previous: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.previousElementSibling() {
                return self.globalStore.storeStdValue(element)
            }
            return -1
        }
    }

    var baseUri: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let uri = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Node)?.getBaseUri() {
                return self.globalStore.storeStdValue(uri)
            }
            return -1
        }
    }

    var body: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let element = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Document)?.body() {
                return self.globalStore.storeStdValue(element)
            }
            return -1
        }
    }

    var text: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.text(trimAndNormaliseWhitespace: true) {
                return self.globalStore.storeStdValue(string)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text(trimAndNormaliseWhitespace: true) {
                return self.globalStore.storeStdValue(string)
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                // https://github.com/scinfu/SwiftSoup/blob/02c63b7be50bda384f22c56c64d347231754a07e/Sources/String.swift#L84-L94
                if !string.isEmpty {
                    let (firstChar, lastChar) = (string.first!, string.last!)
                    if firstChar.isWhitespace || lastChar.isWhitespace || firstChar == "\n" || lastChar == "\n" {
                        return self.globalStore.storeStdValue(string.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var untrimmedText: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.text(trimAndNormaliseWhitespace: false) {
                return self.globalStore.storeStdValue(string)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text(trimAndNormaliseWhitespace: false) {
                return self.globalStore.storeStdValue(string)
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var ownText: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.ownText() {
                return self.globalStore.storeStdValue(string)
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var data: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.data() {
                return self.globalStore.storeStdValue(string)
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var array: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let array = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.array() {
                return self.globalStore.storeStdValue(array)
            }
            return -1
        }
    }

    var html: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.html() {
                return self.globalStore.storeStdValue(string)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.html() {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var outerHtml: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.outerHtml() {
                return self.globalStore.storeStdValue(string)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.outerHtml() {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var escape: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.text() {
                return self.globalStore.storeStdValue(Entities.escape(string))
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text() {
                return self.globalStore.storeStdValue(Entities.escape(string))
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                return self.globalStore.storeStdValue(Entities.escape(string))
            }
            return -1
        }
    }

    var unescape: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Elements)?.text() {
                return self.globalStore.storeStdValue((try? Entities.unescape(string)) ?? string)
            } else if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.text() {
                return self.globalStore.storeStdValue((try? Entities.unescape(string)) ?? string)
            } else if let string = self.globalStore.readStdValue(descriptor) as? String {
                return self.globalStore.storeStdValue((try? Entities.unescape(string)) ?? string)
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
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var tagName: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.tagName() {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var className: (Int32) -> Int32 {
        { descriptor in
            guard descriptor >= 0 else { return -1 }
            if let string = try? (self.globalStore.readStdValue(descriptor) as? SwiftSoup.Element)?.className() {
                return self.globalStore.storeStdValue(string)
            }
            return -1
        }
    }

    var hasClass: (Int32, Int32, Int32) -> Int32 {
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

    var hasAttr: (Int32, Int32, Int32) -> Int32 {
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

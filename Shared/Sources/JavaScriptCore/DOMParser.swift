//
//  DOMParser.swift
//  Aidoku
//
//  Created by Skitty on 1/13/23.
//

import JavaScriptCore
import SwiftSoup

@objc protocol DOMParserExports: JSExport {
    func parseFromString(_ string: String, _ contentType: String) -> Document?
}

class DOMParser: NSObject, DOMParserExports {
    func parseFromString(_ string: String, _ contentType: String) -> Document? {
        if let result = try? SwiftSoup.parse(string) {
            return Document(document: result)
        } else {
            return nil
        }
    }
}

@objc protocol DocumentExports: JSExport {
    func querySelectorAll(_ query: String) -> NodeList
}

class Document: NSObject {
    var swiftSoupDocument: SwiftSoup.Document

    init(document: SwiftSoup.Document) {
        self.swiftSoupDocument = document
    }
}

extension Document: DocumentExports {
    func querySelectorAll(_ query: String) -> NodeList {
        if let elements = try? swiftSoupDocument.select(query) {
            return NodeList(elements: elements)
        } else {
            return NodeList()
        }
    }
}

@objc protocol NodeListExports: JSExport {
    var length: Int { get }
    func item(_ index: Int) -> Node?
}

class NodeList: NSObject, NodeListExports {
    var swiftSoupElements: SwiftSoup.Elements?

    var length: Int {
        swiftSoupElements?.count ?? 0
    }

    init(elements: SwiftSoup.Elements? = nil) {
        self.swiftSoupElements = elements
    }

    func item(_ index: Int) -> Node? {
        guard let elements = swiftSoupElements else { return nil }
        return Element(element: elements.get(index))
    }
}

@objc protocol NodeExports: JSExport {
    var nodeType: NodeType { get }
    var textContent: String? { get }
}

@objc enum NodeType: Int16 {
    case ELEMENT_NODE = 1
    case ATTRIBUTE_NODE = 2
    case TEXT_NODE = 3
    case CDATA_SECTION_NODE = 4
    case PROCESSING_INSTRUCTION_NODE = 7
    case COMMENT_NODE = 8
    case DOCUMENT_NODE = 9
    case DOCUMENT_TYPE_NODE = 10
    case DOCUMENT_FRAGMENT_NODE = 11
}

class Node: NSObject, NodeExports {

    var swiftSoupElement: SwiftSoup.Element

    init(element: SwiftSoup.Element) {
        self.swiftSoupElement = element
    }

    var nodeType: NodeType {
        .ELEMENT_NODE
    }

    var textContent: String? {
        try? swiftSoupElement.text()
    }
}

@objc protocol ElementExports: JSExport {
    var attributes: AttrNamedNodeMap { get }
    func hasAttributes() -> Bool
    func querySelectorAll(_ query: String) -> NodeList
}

class Element: Node, ElementExports {

    var attributes: AttrNamedNodeMap {
        AttrNamedNodeMap(items: swiftSoupElement.getAttributes()?.asList().map { Attr(attribute: $0) } ?? [])
    }

    func hasAttributes() -> Bool {
        !attributes.items.isEmpty
    }

    func querySelectorAll(_ query: String) -> NodeList {
        if let elements = try? swiftSoupElement.select(query) {
            return NodeList(elements: elements)
        } else {
            return NodeList()
        }
    }
}

@objc protocol NamedNodeMapExports: JSExport {
    var length: Int { get }
    func item(_ index: Int) -> Attr?
}

class AttrNamedNodeMap: NSObject, NamedNodeMapExports {

    var items: [Attr]

    init(items: [Attr]) {
        self.items = items
    }

    var length: Int {
        items.count
    }

    func item(_ index: Int) -> Attr? {
        items[index]
    }
}

@objc protocol AttrExports: JSExport {
    var name: String { get }
    var value: String { get }
}

class Attr: NSObject, AttrExports {
    var swiftSoupAttribute: SwiftSoup.Attribute

    init(attribute: SwiftSoup.Attribute) {
        self.swiftSoupAttribute = attribute
    }

    var name: String {
        swiftSoupAttribute.getKey()
    }
    var value: String {
        swiftSoupAttribute.getValue()
    }
}

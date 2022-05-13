//
//  Filter.swift
//  Aidoku
//
//  Created by Skitty on 1/12/22.
//

import Foundation
import WasmInterpreter

enum FilterType: Int {
    case base = 0
    case group = 1
    case text = 2
    case check = 3
    case select = 4
    case sort = 5
    case sortSelection = 6
    case title = 7
    case author = 8
    case genre = 9
}

class FilterBase: KVCObject, Identifiable, Equatable, NSCopying {
    static func == (lhs: FilterBase, rhs: FilterBase) -> Bool {
        lhs.id == rhs.id
    }

    var name: String

    var type: FilterType {
        .base
    }

    init(name: String) {
        self.name = name
    }

    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "type": return type.rawValue
        case "name": return self.name
        default: return nil
        }
    }

    func copy(with zone: NSZone? = nil) -> Any {
        FilterBase(name: self.name)
    }
}

class Filter<T>: FilterBase {
    var value: T
    var defaultValue: T

    init(name: String, value: T) {
        self.defaultValue = value
        self.value = value
        super.init(name: name)
    }

    override func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "value": return value
        case "default": return defaultValue
        default: return super.valueByPropertyName(name: name)
        }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        Filter(name: self.name, value: value)
    }
}

// Just used for select and sort options internally
class StringFilter: Filter<String> {
    init(value: String = "") {
        super.init(name: value, value: value)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        StringFilter(value: value)
    }
}

// MARK: Text
class TextFilter: Filter<String> {
    override var type: FilterType {
        .text
    }

    override init(name: String, value: String = "") {
        super.init(name: name, value: value)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        TextFilter(name: name, value: value)
    }
}

// MARK: Check
class CheckFilter: Filter<Bool?> {
    var canExclude: Bool
    var id: JsonAnyValue?

    override var type: FilterType {
        .check
    }

    init(name: String, canExclude: Bool, id: JsonAnyValue? = nil, value: Bool? = nil) {
        self.canExclude = canExclude
        self.id = id
        super.init(name: name, value: value)
    }

    override func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "canExclude": return canExclude
        case "id": return id?.toRaw()
        default: return super.valueByPropertyName(name: name)
        }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        CheckFilter(name: name, canExclude: canExclude, id: id, value: value)
    }
}

// MARK: Select
class SelectFilter: Filter<Int> {
    var options: [String]

    override var type: FilterType {
        .select
    }

    init(name: String, options: [String], value: Int = 0) {
        self.options = options
        super.init(name: name, value: value)
    }

    override func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "options": return options
        default: return super.valueByPropertyName(name: name)
        }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        SelectFilter(name: name, options: options, value: value)
    }
}

// MARK: Sort
class SortSelection: FilterBase {
    var index: Int
    var ascending: Bool

    override var type: FilterType {
        .sortSelection
    }

    init(index: Int, ascending: Bool) {
        self.index = index
        self.ascending = ascending
        super.init(name: "")
    }

    override func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "index": return index
        case "ascending": return ascending
        default: return nil
        }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        SortSelection(index: index, ascending: ascending)
    }
}

class SortFilter: Filter<SortSelection> {
    var options: [String]
    var canAscend: Bool

    override var type: FilterType {
        .sort
    }

    init(name: String, options: [String], canAscend: Bool = true, value: SortSelection = SortSelection(index: 0, ascending: false)) {
        self.options = options
        self.canAscend = canAscend
        super.init(name: name, value: value)
    }

    override func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "options": return options
        case "canAscend": return canAscend
        default: return super.valueByPropertyName(name: name)
        }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        // swiftlint:disable:next force_cast
        SortFilter(name: name, options: options, canAscend: canAscend, value: value.copy(with: zone) as! SortSelection)
    }
}

// MARK: Group
class GroupFilter: Filter<Any?> {
    var filters: [FilterBase]

    override var type: FilterType {
        .group
    }

    init(name: String, filters: [FilterBase]) {
        self.filters = filters
        super.init(name: name, value: nil)
    }

    override func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "filters": return filters
        default: return super.valueByPropertyName(name: name)
        }
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        GroupFilter(name: name, filters: filters)
    }
}

// MARK: Common types
class TitleFilter: TextFilter {
    override var type: FilterType {
        .title
    }

    init(value: String = "") {
        super.init(name: "Title", value: value)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        TitleFilter(value: value)
    }
}

class AuthorFilter: TextFilter {
    override var type: FilterType {
        .author
    }

    init(value: String = "") {
        super.init(name: "Author", value: value)
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        AuthorFilter(value: value)
    }
}

class GenreFilter: CheckFilter {
    override var type: FilterType {
        .genre
    }

    override func copy(with zone: NSZone? = nil) -> Any {
        GenreFilter(name: name, canExclude: canExclude, id: id, value: value)
    }
}

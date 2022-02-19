//
//  Filter.swift
//  Aidoku
//
//  Created by Skitty on 1/12/22.
//

import Foundation
import WasmInterpreter

enum FilterType: Int {
    case note = 0 // just plain text, a note
    case text = 1 // enterable text
    case check = 2 // multi option include or exclude
    case select = 3 // single option selection
    case sort = 4 // sort group
    case sortOption = 5 // sort option
    case group = 6 // filter group
    case genre = 7
}

struct SortOption: KVCObject, Equatable {
    let index: Int
    let name: String
    let ascending: Bool
    
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "index": return index
        case "name": return self.name
        case "ascending": return ascending
        default: return nil
        }
    }
}

struct Filter: KVCObject, Identifiable, Equatable {
    
    static func == (lhs: Filter, rhs: Filter) -> Bool {
        lhs.id == rhs.id && lhs.value as? Int ?? 0 == rhs.value as? Int ?? 0
    }
    
    var id: String {
        name
    }
    
    let type: FilterType
    var name: String
    var value: Any? = nil
    var defaultValue: Any? = nil
    
    init(type: FilterType, name: String, value: Any? = nil, defaultValue: Any? = nil) {
        self.type = type
        self.name = name
        self.value = value
        self.defaultValue = defaultValue
    }
    
    // Note
    init(text: String) {
        self.type = .note
        self.name = text
    }
    
    // Text
    init(name: String, value: String? = nil) {
        self.type = .text
        self.name = name
        self.value = value
    }
    
    // Check (and Genre)
    init(type: FilterType = .check, name: String, canExclude: Bool, default defaultValue: Int = 0) {
        self.type = type
        self.name = name
        self.value = canExclude
        self.defaultValue = defaultValue
    }
    
    // Select
    init(name: String, options: [String], default defaultValue: Int = 0) {
        self.type = .select
        self.name = name
        self.value = options
        self.defaultValue = defaultValue
    }
    
    // Sort
    init(name: String, options: [Filter], value: SortOption? = nil, default defaultValue: SortOption? = nil) {
        self.type = .sort
        self.name = name
        if let value = value {
            self.value = value
        } else {
            self.value = options
        }
        self.defaultValue = defaultValue
    }
    
    // Sort Option
    init(name: String, index: Int = 0, canReverse: Bool) {
        self.type = .sortOption
        self.name = name
        self.value = SortOption(index: index, name: name, ascending: canReverse)
    }
    
    // Group
    init(name: String, filters: [Filter]) {
        self.type = .group
        self.name = name
        self.value = filters as Any
    }
    
    func toStructPointer(vm: WasmInterpreter, memory: WasmMemory) -> Int32 {
        let namePointer = vm.write(string: name, memory: memory)
        var valuePointer: Int32 = 0
        if let str = value as? String {
            valuePointer = vm.write(string: str, memory: memory)
        }
        return vm.write(data: [Int32(type.rawValue), namePointer, valuePointer], memory: memory)
    }
    
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "type": return type.rawValue
        case "name": return self.name
        case "value": return value
        case "default": return defaultValue
        default: return nil
        }
    }
}

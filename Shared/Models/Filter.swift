//
//  Filter.swift
//  Aidoku
//
//  Created by Skitty on 1/12/22.
//

import Foundation
import WasmInterpreter

enum FilterType: Int {
    case text = 0
    case option = 1
    case sort = 2
    case group = 3
}

enum FilterOption: Int {
    case text = 0
    case option = 1
    case sort = 2
    case group = 3
}

struct Filter: KVCObject, Identifiable, Equatable {
    static func == (lhs: Filter, rhs: Filter) -> Bool {
        lhs.id == rhs.id
    }
    
    var id: String {
        name
    }
    
    let type: FilterType
    let name: String
    var value: Any?
    var defaultValue: Any? = nil
    
    var secondaryType: Int?
    
    init(type: FilterType, name: String, value: Any? = nil, defaultValue: Any? = nil) {
        self.type = type
        self.name = name
        self.value = value
        self.defaultValue = defaultValue
    }
    
    init(name: String, value: String? = nil) {
        self.type = .text
        self.name = name
        self.value = value
    }
    
    init(name: String, filters: [Filter], nested: Bool = false) {
        self.type = .group
        self.name = name
        self.value = filters as Any
        self.secondaryType = nested ? 1 : 0
    }
    
    init(name: String, canExclude: Bool, default defaultValue: Int = 0) {
        self.type = .option
        self.name = name
        self.value = canExclude as Any
        self.defaultValue = defaultValue as Any
    }
    
    init(name: String, canReverse: Bool, default defaultValue: Int = 0) {
        self.type = .sort
        self.name = name
        self.value = canReverse as Any
        self.defaultValue = defaultValue as Any
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
        default: return nil
        }
    }
}

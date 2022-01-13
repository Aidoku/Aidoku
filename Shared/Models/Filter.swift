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
    case bool
    case group
}

struct Filter {
    let type: FilterType
    let name: String
    let value: Any?
    
    init(type: FilterType, name: String, value: Any? = nil) {
        self.type = type
        self.name = name
        self.value = value
    }
    
    init(name: String, value: String? = nil) {
        self.type = .text
        self.name = name
        self.value = value
    }
    
    init(name: String, filters: [Filter]) {
        self.type = .group
        self.name = name
        self.value = filters as Any
    }
    
    init(name: String, canExclude: Bool) {
        self.type = .bool
        self.name = name
        self.value = canExclude as Any
    }
    
    func toStructPointer(vm: WasmInterpreter, memory: WasmMemory) -> Int32 {
        let namePointer = vm.write(string: name, memory: memory)
        var valuePointer: Int32 = 0
        if let str = value as? String {
            valuePointer = vm.write(string: str, memory: memory)
        }
        return vm.write(data: [Int32(type.rawValue), namePointer, valuePointer], memory: memory)
    }
}

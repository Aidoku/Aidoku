//
//  WasmMemory.swift
//  Aidoku
//
//  Created by Skitty on 1/8/22.
//

import Foundation
import WasmInterpreter
import CWasm3

struct WasmAllocation {
    var address: Int32
    var size: Int32
}

class WasmMemory {
    let vm: WasmInterpreter
    
    let base: Int32
    var allocations = [WasmAllocation]()
    
//    var mallocCount = 0
//    var freeCount = 0
    
    init(vm: WasmInterpreter) {
        self.vm = vm
        let globalBase = try? self.vm.globalValue(name: "__heap_base")
        self.base = globalBase ?? (try? self.vm.call("get_heap_base")) ?? Int32(66992)
    }
    
    var malloc: (Int32) -> Int32 {
        { size in
//            self.mallocCount += 1
            var location: Int32 = self.base
            var i = 0
            for allocation in self.allocations {
                let available = allocation.address - location
                if available > size {
                    self.allocations.insert(WasmAllocation(address: location, size: size), at: i)
                    return location
                } else {
                    location = allocation.address + allocation.size + 1
                }
                i += 1
            }
            let pageCount = Int(self.vm.runtime.pointee.memory.numPages)
            let pageSize = 64 * 1024
            if location + size >= pageCount * pageSize {
                let numNewPages = ceil(Double(Int(location + size) - (pageCount * pageSize)) / Double(pageSize))
                ResizeMemory(self.vm.runtime, UInt32(pageCount + Int(numNewPages)))
            }
            self.allocations.append(WasmAllocation(address: location, size: size))
            return location
        }
    }
    
    var free: (Int32) -> Void {
        { addr in
            guard addr >= self.base else { return }
//            self.freeCount += 1
            if let index = self.allocations.firstIndex(where: { $0.address == addr }) {
                self.allocations.remove(at: index)
//                if self.freeCount % 10 == 0 || self.allocations.count == 0 {
//                    print("-> \(self.mallocCount) \(self.freeCount) \(self.allocations.count)")
//                }
            } else {
                print("ADDRESS TO FREE NOT FOUND (\(addr))")
            }
        }
    }
}

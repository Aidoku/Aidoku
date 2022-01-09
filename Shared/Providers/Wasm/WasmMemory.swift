//
//  WasmMemory.swift
//  Aidoku
//
//  Created by Skitty on 1/8/22.
//

import Foundation
import WebAssembly

struct WasmAllocation {
    var address: Int32
    var size: Int32
}

class WasmMemory {
    let vm: Interpreter
    
    let header: Int32 = 128 * 1024 // 128 kb
    var allocations = [WasmAllocation]()
    
//    var mallocCount = 0
//    var freeCount = 0
    
    init(vm: Interpreter) {
        self.vm = vm
    }
    
    var malloc: (Int32) -> Int32 {
        { size in
//            self.mallocCount += 1
            var location: Int32 = self.header
            var i = 0
            for allocation in self.allocations {
                let available = location - (allocation.address + allocation.size)
                if available > size {
                    self.allocations.insert(WasmAllocation(address: location - size, size: size), at: i)
                    return location - size
                } else {
                    location = allocation.address - 1
                }
                i += 1
            }
            if location <= size {
                print("[!] RAN OUT OF MEMORY")
                print("allocation count: \(self.allocations.count)")
                return 0
            }
            self.allocations.append(WasmAllocation(address: location - size, size: size))
            return location - size
        }
    }
    
    var free: (Int32) -> Void {
        { addr in
//            self.freeCount += 1
            if let index = self.allocations.firstIndex(where: { $0.address == addr }) {
                self.allocations.remove(at: index)
//                if self.freeCount % 10 == 0 || self.allocations.count == 0 {
//                    print("-> \(self.mallocCount) \(self.freeCount) \(self.allocations.count)")
//                }
            } else {
                print("ADDRESS TO FREE NOT FOUND")
            }
        }
    }
}

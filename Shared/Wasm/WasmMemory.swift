//
//  WasmMemory.swift
//  Aidoku
//
//  Created by Skitty on 1/8/22.
//

import Foundation
import WasmInterpreter
import CWasm3

class WasmMemory {

    let vm: WasmInterpreter

    init(vm: WasmInterpreter) {
        self.vm = vm
    }

//    var sizes: [Int32: Int32] = [:]

    var malloc: (Int32) -> Int32 {
        { size in
            let addr: Int32 = (try? self.vm.call("allocate", size)) ?? 0
//            self.sizes[addr] = size
            return addr
        }
    }

    var free: (Int32) -> Void {
        { addr in
            try? self.vm.call("deallocate", addr, 0) // self.sizes[addr] ?? 0)
//            self.sizes.removeValue(forKey: addr)
        }
    }
}

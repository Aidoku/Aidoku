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
    
    init(vm: WasmInterpreter) {
        self.vm = vm
    }
    
    var malloc: (Int32) -> Int32 {
        { size in
            (try? self.vm.call("allocate", size)) ?? 0
        }
    }
    
    var free: (Int32) -> Void {
        { addr in
            try? self.vm.call("deallocate", addr)
        }
    }
}

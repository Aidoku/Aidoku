//
//  Unreachable.swift
//  Aidoku
//
//  Created by skitty on 8/25/26.
//

@inline(__always)
func unreachable() -> Never {
    unsafeBitCast((), to: Never.self)
}

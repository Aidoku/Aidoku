//
//  KVCObject.swift
//  Aidoku
//
//  Created by Skitty on 1/14/22.
//

import Foundation

protocol KVCObject {
    func valueByPropertyName(name: String) -> Any?
}

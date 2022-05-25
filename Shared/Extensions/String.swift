//
//  String.swift
//  Aidoku
//
//  Created by Skitty on 5/25/22.
//

import Foundation

extension String {

    func take(first: Int) -> String {
        String(self[self.startIndex..<self.index(self.startIndex, offsetBy: first)])
    }

    func take(last: Int) -> String {
        String(self[self.index(self.endIndex, offsetBy: -last)..<self.endIndex])
    }

    func drop(first: Int) -> String {
        String(self[self.index(self.startIndex, offsetBy: first)..<self.endIndex])
    }

    func drop(last: Int) -> String {
        String(self[self.startIndex..<self.index(self.endIndex, offsetBy: -last)])
    }
}

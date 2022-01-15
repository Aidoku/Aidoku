//
//  Chapter.swift
//  Aidoku
//
//  Created by Skitty on 12/22/21.
//

import Foundation

struct Chapter: KVCObject, Identifiable, Hashable {
    let id: String
    let title: String?
    let chapterNum: Float
    let volumeNum: Int?
    
    init(id: String, title: String?, chapterNum: Float, volumeNum: Int? = nil) {
        self.id = id
        self.title = title == "" ? nil : title
        self.chapterNum = chapterNum
        self.volumeNum = volumeNum
    }
    
    func valueByPropertyName(name: String) -> Any? {
        switch name {
        case "id": return id
        case "title": return title
        case "chapterNum": return chapterNum
        case "volumeNum": return volumeNum
        default: return nil
        }
    }
}

//
//  SavedSearch.swift
//  Aidoku
//
//  Created by Skitty on 3/2/26.
//

import AidokuRunner

struct SavedSearch: Codable {
    let name: String
    let search: String?
    let filters: [FilterValue]
}

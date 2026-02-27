//
//  FilterGroup.swift
//  Aidoku
//
//  Created by Skitty on 2/27/26.
//

struct FilterGroup: Equatable {
    let title: String
    let filters: [LibraryViewModel.LibraryFilter]

    static func == (lhs: FilterGroup, rhs: FilterGroup) -> Bool {
        lhs.title == rhs.title
    }
}

//
//  ProviderManager.swift
//  Aidoku
//
//  Created by Skitty on 12/29/21.
//

import Foundation

class ProviderManager {
    
    static let shared = ProviderManager()
    
    let providers: [String: MangaProvider] = [
        "xyz.skitty.mangadex": MangaDexProvider(),
        "xyz.skitty.tcbscans": TCBScansProvider()
    ]

    func provider(for id: String) -> MangaProvider {
        providers[id] ?? MangaDexProvider()
    }
    
}

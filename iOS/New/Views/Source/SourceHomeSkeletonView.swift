//
//  SourceHomeSkeletonView.swift
//  Aidoku
//
//  Created by Skitty on 4/1/25.
//

import AidokuRunner
import SwiftUI

struct SourceHomeSkeletonView: View {
    let source: AidokuRunner.Source

    @State private var components: [[Int]]

    init(source: AidokuRunner.Source) {
        self.source = source
        let components = UserDefaults.standard.array(forKey: "\(source.key).homeComponents") as? [Int]
        if let components {
            self._components = .init(initialValue: components.chunked(into: 2))
        } else {
            // fall back to default skeleton layout
            self._components = .init(initialValue: [[1, 0], [3, 5], [2, 0]])
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            ForEach(components.indices, id: \.self) { idx in
                switch components[idx][0] {
                    case 0:
                        PlaceholderHomeImageScrollerView()
                    case 1:
                        PlaceholderMangaHomeBigScroller()
                    case 2:
                        PlaceholderMangaScroller()
                    case 3, 4:
                        PlaceholderMangaHomeList(itemCount: components[idx][1])
                    case 5:
                        PlaceholderHomeFiltersView()
                    case 6:
                        PlaceholderHomeLinksView()
                    default:
                        EmptyView()
                }
            }
        }
    }
}

#Preview {
    SourceHomeSkeletonView(source: .demo())
        .padding()
}

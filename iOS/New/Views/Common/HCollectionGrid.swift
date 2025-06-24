//
//  HCollectionGrid.swift
//  Aidoku
//
//  Created by Skitty on 3/13/24.
//

import SwiftUI

// splits items into a specified number of rows
// intended to be used inside of a horizontal scroll view
struct HCollectionGrid<Data, ID, Content>: View
where
    Data: RandomAccessCollection & Sendable,
    ID: Hashable & Sendable,
    Content: View & Sendable
{
    private let rows: Int
    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    private let content: ((Data.Element) -> Content)

    private let horizontalSpacing: CGFloat
    private let verticalSpacing: CGFloat

    @State private var contentSize = CGSize.zero

    var body: some View {
        VStack {
            self.generateContent()
        }
        .frame(width: contentSize.width, height: contentSize.height)
    }

    @ViewBuilder
    private func generateContent() -> some View {
        var alignments = Array(repeating: CGFloat.zero, count: rows)
        var currentIndex = -1
        var top: CGFloat = 0

        ZStack(alignment: .topLeading) {
            ForEach(data, id: id) { element in
                content(element)
            }
            .fixedSize(horizontal: true, vertical: false)
            .alignmentGuide(.leading) { dimensions in
                currentIndex += 1

                if currentIndex + 1 > rows {
                    currentIndex = 0
                }

                let leading = alignments[currentIndex..<min(currentIndex + 1, rows)].min()!
                top = CGFloat(-currentIndex) * (dimensions.height + verticalSpacing)
                for index in currentIndex..<min(currentIndex + 1, rows) {
                    alignments[index] = leading - dimensions.width - horizontalSpacing
                }

                return leading
            }
            .alignmentGuide(.top) { _ in
                top
            }

            Color.clear
                .frame(width: 1, height: 1)
                .hidden()
                .alignmentGuide(.leading) { _ in
                    alignments = Array(repeating: .zero, count: rows)
                    currentIndex = -1
                    top = 0
                    return 0
                }
        }
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear {
                    contentSize = geometry.size
                }
                .onChange(of: geometry.size) { newValue in
                    contentSize = newValue
                }
        })
    }
}

// MARK: Initializers

// extension HCollectionGrid where ID == Data.Element.ID, Data.Element: Identifiable {
//    init(
//        rows: Int,
//        verticalSpacing: CGFloat = 0,
//        horizontalSpacing: CGFloat = 0,
//        _ data: Data,
//        @ViewBuilder content: @escaping (Data.Element) -> Content
//    ) {
//        self.rows = max(1, rows)
//        self.data = data
//        self.id = \.id
//        self.content = content
//        self.verticalSpacing = verticalSpacing
//        self.horizontalSpacing = horizontalSpacing
//    }
// }

extension HCollectionGrid {
    init(
        rows: Int,
        verticalSpacing: CGFloat = 0,
        horizontalSpacing: CGFloat = 0,
        _ data: Data,
        id: KeyPath<Data.Element,
        ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.rows = max(1, rows)
        self.data = data
        self.id = id
        self.content = content
        self.verticalSpacing = verticalSpacing
        self.horizontalSpacing = horizontalSpacing
    }
}

#Preview {
    ScrollView(.horizontal) {
        HCollectionGrid(
            rows: 6,
            verticalSpacing: 8,
            horizontalSpacing: 8,
            Array(1...100),
            id: \.self
        ) { item in
            Text("Item \(item)")
                .foregroundStyle(.white)
                .padding(4)
                .background(.black)
        }
        .background(.green)
    }
    .background(.red)
}

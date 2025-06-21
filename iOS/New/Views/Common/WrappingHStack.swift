//
//  WrappingHStack.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import SwiftUI

// hstack of items that wraps to the next line when it runs out of horizontal space
struct WrappingHStack<Data, ID, Content>: View where Data: RandomAccessCollection, ID: Hashable, Content: View {
    private let data: Data
    private let id: KeyPath<Data.Element, ID>
    private let content: ((Data.Element) -> Content)

    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack {
            GeometryReader { geometry in
                self.generateContent(in: geometry)
            }
        }
        .frame(height: totalHeight)
    }

    @ViewBuilder
    private func generateContent(in geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            let holder = TagModifier.WidthHeightHolder()
            ForEach(data, id: id) { tag in
                content(tag)
                    .modifier(TagModifier(
                        proxyWidth: geometry.size.width,
                        holder: holder,
                        last: tag[keyPath: id] == data.last![keyPath: id]
                    ))
            }
        }
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear {
                    totalHeight = geometry.frame(in: .local).size.height
                }
                .onChange(of: geometry.size) { _ in
                    totalHeight = geometry.frame(in: .local).size.height
                }
        })
    }
}

// MARK: Initializers

// extension WrappingHStack where ID == Data.Element.ID, Data.Element: Identifiable {
//    init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
//        self.data = data
//        self.id = \.id
//        self.content = content
//    }
// }

extension WrappingHStack {
    init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.id = id
        self.content = content
    }
}

// MARK: Tag Modifier

private struct TagModifier: ViewModifier {
    let proxyWidth: CGFloat
    let holder: WidthHeightHolder
    let last: Bool

    func body(content: Self.Content) -> some View {
        content
            .alignmentGuide(.leading) { @Sendable d in
                holder.sync {
                    if abs(holder.width - d.width) > proxyWidth {
                        holder.width = 0
                        holder.height -= d.height
                    }
                    let result = holder.width
                    if last {
                        holder.width = 0
                    } else {
                        holder.width -= d.width
                    }
                    return result
                }
            }
            .alignmentGuide(.top) { @Sendable _ in
                holder.sync {
                    let result = holder.height
                    if last {
                        holder.height = 0
                    }
                    return result
                }
            }
    }

    class WidthHeightHolder: @unchecked Sendable {
        var width = CGFloat.zero
        var height = CGFloat.zero

        private let queue = DispatchQueue(label: "WidthHeightHolder")

        func sync<T>(_ body: () throws -> T) rethrows -> T {
            try queue.sync(execute: body)
        }
    }
}

#Preview {
    WrappingHStack(Array(1...10), id: \.self) { item in
        Text("Item \(item)")
            .foregroundStyle(.white)
            .padding(4)
            .background(.black)
    }
    .background(.red)
}

//
//  SourceListCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/10/22.
//

import SwiftUI
import Kingfisher

struct SourceListCell: View {
    let source: Source
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 10) {
                KFImage(source.url.appendingPathComponent("Icon.png"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 48 * 0.225, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 48 * 0.225).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                VStack(alignment: .leading) {
                    HStack {
                        Text(source.info.name)
                            .foregroundColor(.label)
                            .lineLimit(1)
                        Text("v" + String(source.info.version))
                            .foregroundColor(.secondaryLabel)
                            .lineLimit(1)
                    }
                    Text(source.id)
                        .foregroundColor(.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(Color.secondaryFill)
            }
            .padding(.horizontal)
            Divider()
                .padding(.leading)
                .padding(.trailing)
        }
    }
}

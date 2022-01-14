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
            HStack(spacing: 8) {
                KFImage(URL(string: "https://skitty.xyz/icon.png"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .cornerRadius(48 * 0.225)
                    .overlay(RoundedRectangle(cornerRadius: 48 * 0.225).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.info.name)
                        .foregroundColor(.label)
                        .lineLimit(1)
                    Text("v0.0." + String(source.info.version))
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

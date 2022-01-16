//
//  ExternalSourceListCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/11/22.
//

import SwiftUI
import Kingfisher

struct ExternalSourceListCell: View {
    let source: ExternalSourceInfo
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 8) {
                KFImage(URL(string: "https://skitty.xyz/aidoku-sources/icons/\(source.icon)"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .cornerRadius(48 * 0.225)
                    .overlay(RoundedRectangle(cornerRadius: 48 * 0.225).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .foregroundColor(.label)
                        .lineLimit(1)
                    Text("v" + String(source.version))
                        .foregroundColor(.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    Task {
                        _ = await SourceManager.shared.importSource(from: URL(string: "https://skitty.xyz/aidoku-sources/sources/\(source.file)")!)
                    }
                } label: {
                    Text("GET")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                }
                .background(.tertiaryFill)
                .cornerRadius(14)
                .frame(width: 72, height: 28)
            }
            .padding(.horizontal)
            Divider()
                .padding(.leading)
                .padding(.trailing)
        }
    }
}

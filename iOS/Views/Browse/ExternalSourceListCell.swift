//
//  ExternalSourceListCell.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 1/11/22.
//

import SwiftUI
import Kingfisher
import SwiftUIX

struct ExternalSourceListCell: View {
    let source: ExternalSourceInfo
    let update: Bool
    
    @State var installing = false
    @State var getText: String
    
    init(source: ExternalSourceInfo, update: Bool = false) {
        self.source = source
        self.update = update
        if update {
            getText = "UPDATE"
        } else {
            getText = "GET"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 8) {
                KFImage(URL(string: "https://skitty.xyz/aidoku-sources/icons/\(source.icon)"))
                    .placeholder {
                        Image("MangaPlaceholder")
                            .resizable()
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .cornerRadius(48 * 0.225)
                    .overlay(RoundedRectangle(cornerRadius: 48 * 0.225).strokeBorder(Color.quaternaryFill, lineWidth: 1))
                VStack(alignment: .leading) {
                    HStack {
                        Text(source.name)
                            .foregroundColor(.label)
                            .lineLimit(1)
                        Text("v" + String(source.version))
                            .foregroundColor(.secondaryLabel)
                            .lineLimit(1)
                    }
                    Text(source.id)
                        .foregroundColor(.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer()
                ZStack(alignment: .trailing) {
                    Button {
                        Task {
                            withAnimation {
                                installing = true
                            }
                            let installedSource = await SourceManager.shared.importSource(from: URL(string: "https://skitty.xyz/aidoku-sources/sources/\(source.file)")!)
                            withAnimation {
                                if installedSource == nil {
                                    getText = "FAILED"
                                }
                                installing = false
                            }
                        }
                    } label: {
                        if installing {
                            ActivityIndicator()
                                .scaleEffect(0.7)
                                .padding(4)
                        } else {
                            Text(getText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, getText != "GET" ? 14 : 18)
                                .padding(.vertical, 4)
                                .transition(.opacity)
                        }
                    }
                }
                .background(.tertiaryFill)
                .cornerRadius(14)
                .frame(height: 28)
                .modifier(AnimatingWidth(width: installing ? 28 : (getText != "GET" ? 90 : 67)))
            }
            .padding(.horizontal)
            Divider()
                .padding(.leading)
                .padding(.trailing)
        }
    }
}

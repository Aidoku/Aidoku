//
//  ExternalSourceTableCell.swift
//  Aidoku
//
//  Created by Skitty on 5/23/25.
//

import SwiftUI

struct ExternalSourceTableCell: View {
    let source: SourceInfo2
    var subtitle: String?

    var onInstall: (() -> Void)?
    var onGet: (() async -> Bool)?

    var body: some View {
        HStack(spacing: 0) {
            SourceIconView(sourceId: source.sourceId, imageUrl: source.iconUrl)
                .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(source.name)
                        .lineLimit(1)
                    Text("v\(source.version)")
                        .foregroundStyle(.secondary)

                    if source.contentRating != .safe {
                        let (text, background) = if source.contentRating == .containsNsfw {
                            ("17+", Color.orange.opacity(0.3))
                        } else {
                            ("18+", Color.red.opacity(0.3))
                        }

                        Text(text)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 10))
                            .padding(.vertical, 3)
                            .padding(.horizontal, 5)
                            .background(background)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.leading, 3)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(
                        source.isMultiLanguage
                            ? NSLocalizedString("MULTI_LANGUAGE")
                            : Locale.current.localizedString(forIdentifier: source.languages[0]) ?? source.languages[0]
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 16))

            Spacer(minLength: 0)

            GetButton {
                if let onGet {
                    return await onGet()
                } else {
                    guard
                        let externalInfo = source.externalInfo,
                        let url = externalInfo.fileURL
                    else { return false }

                    let result = try? await SourceManager.shared.importSource(from: url)

                    if result != nil {
                        onInstall?()
                    }

                    return result != nil
                }
            }
        }
        .padding(.vertical, 4)
    }
}

//
//  FilterLabelView.swift
//  Aidoku
//
//  Created by Skitty on 10/16/23.
//

import SwiftUI

struct FilterLabelView: View {
    let name: String
    var badgeCount: Int?
    var active = false
    var chevron = true
    var icon: String?

    @Environment(\.colorScheme) private var colorScheme

    private var highlighted: Bool {
        active || badgeCount ?? 0 > 0
    }

    // show badge if count (number of subfilters enabled) is greater than 1
    private var hasBadge: Bool {
        badgeCount ?? 1 > 1
    }

    var body: some View {
        let label = HStack(spacing: 4) {
            if let badgeCount, hasBadge {
                FilterBadgeView(count: badgeCount)
            }

            Text(name)
                .opacity(highlighted ? 1 : 0.6)
                .foregroundColor(highlighted && colorScheme == .light ? .accentColor : .primary)

            Group {
                if let icon {
                    Image(systemName: icon)
                } else if chevron {
                    Image(systemName: "chevron.down")
                }
            }
            .foregroundColor(
                highlighted
                    ? (colorScheme == .light ? .accentColor : .primary)
                    : .init(uiColor: .tertiaryLabel)
            )
        }
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, hasBadge ? 6 : 8)
        .font(.caption.weight(.medium))

        if #available(iOS 26.0, *) {
            label
                .glassEffect(
                    highlighted ? .regular.tint(.accentColor.opacity(highlighted && colorScheme == .light ? 0.1 : 1)) : .regular,
                    in: .capsule
                )
        } else {
            label
                .background(
                    RoundedRectangle(cornerRadius: 100) // enough to make it fully rounded
                        .foregroundColor(
                            highlighted ? .accentColor : .init(uiColor: .secondarySystemFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 100)
                                .stroke(Color(uiColor: .tertiarySystemFill), style: .init(lineWidth: 1))
                        )
                        .opacity(highlighted && colorScheme == .light ? 0.1 : 1)
                )
        }
    }
}

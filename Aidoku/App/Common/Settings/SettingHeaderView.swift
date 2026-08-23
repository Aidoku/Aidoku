//
//  SettingHeaderView.swift
//  Aidoku
//
//  Created by Skitty on 10/8/25.
//

import AidokuRunner
import SwiftUI

struct SettingHeaderView: View {
    var source: AidokuRunner.Source?
    let icon: Icon
    let title: String
    let subtitle: AttributedString

    init(
        source: AidokuRunner.Source? = nil,
        icon: Icon,
        title: String,
        subtitle: String,
        learnMoreUrl: URL? = nil
    ) {
        self.source = source
        self.icon = icon
        self.title = title

        if let learnMoreUrl {
            var string = AttributedString(subtitle + " " + NSLocalizedString("LEARN_MORE"))
            if let range = string.range(of: NSLocalizedString("LEARN_MORE")) {
                string[range].link = learnMoreUrl
            }
            self.subtitle = string
        } else {
            self.subtitle = AttributedString(subtitle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Self.iconView(source: source, icon: icon, size: 60)
                .padding(.bottom, 11)

            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Icon {
        case system(name: String, color: String, inset: Int = 5)
        case url(String)
        case raw(Image)

        static func from(_ value: PageSetting.Icon) -> Self {
            switch value {
                case let .system(name, color, inset):
                    .system(name: name, color: color, inset: inset)
                case let .url(string):
                    .url(string)
            }
        }
    }

    @ViewBuilder
    static func iconView(source: AidokuRunner.Source?, icon: Icon, size: CGFloat) -> some View {
        switch icon {
            case let .system(name, color, inset):
                Image(systemName: name)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(.white)
                    .aspectRatio(contentMode: .fit)
                    .padding(CGFloat(inset) / 29 * size)
                    .frame(width: size, height: size)
                    .background(color.toColor())
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
            case let .url(string):
                SourceImageView(
                    source: source,
                    imageUrl: string,
                    width: size,
                    height: size,
                    downsampleWidth: size * 2
                )
                .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
            case let .raw(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.26))
        }
    }
}

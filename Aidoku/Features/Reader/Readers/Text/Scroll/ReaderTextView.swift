//
//  ReaderTextView.swift
//  Aidoku
//
//  Created by skitty on 3/16/26.
//

import AidokuRunner
import SwiftUI

struct ReaderTextView: View {
    let source: AidokuRunner.Source?
    let text: String?
    let fontFamily: String
    let fontSize: Double
    let lineSpacing: Double
    let horizontalPadding: Double
    let textColor: Color

    init(
        source: AidokuRunner.Source?,
        page: Page?,
        fontFamily: String,
        fontSize: Double,
        lineSpacing: Double,
        horizontalPadding: Double,
        textColor: Color,
        textOverride: String? = nil
    ) {
        self.source = source
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.horizontalPadding = horizontalPadding
        self.textColor = textColor

        self.text = textOverride ?? page.flatMap(ReaderTextContent.load)
    }

    var body: some View {
        if let text {
            MarkdownView(
                text,
                fontFamily: fontFamily,
                fontSize: fontSize,
                lineSpacing: lineSpacing,
                horizontalPadding: horizontalPadding,
                textColor: textColor
            )
            .id(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea()
        }
    }
}

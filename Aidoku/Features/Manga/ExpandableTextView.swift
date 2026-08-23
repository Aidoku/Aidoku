//
//  ExpandableTextView.swift
//  Aidoku
//
//  Created by Skitty on 8/18/23.
//

import MarkdownUI
import SafariServices
import SwiftUI

struct ExpandableTextView: View {
    let text: String
    @Binding var expanded: Bool

    @State private var truncated = false
    @State private var moreButtonHeight: CGFloat = 0

    @EnvironmentObject private var path: NavigationCoordinator

    var textUntilNewline: String {
        // first four lines up to either new paragraph or separator
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .prefix(4)
            .prefix { !$0.isEmpty && !$0.contains("___") }
            .joined(separator: "  \n")
    }

    static let markdownTheme = Theme()
        .paragraph { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                }
                .lineSpacing(0)
                .foregroundStyle(.secondary)
        }

    var body: some View {
        let text = expanded ? text : textUntilNewline
        ZStack(alignment: .bottomTrailing) {
            Markdown(text)
                .markdownTheme(Self.markdownTheme)
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
                            return .systemAction
                        }

                        Task {
                            let deepLinkHandled = await appDelegate.handleDeepLink(url: url)
                            if !deepLinkHandled && (url.scheme == "http" || url.scheme == "https") {
                                path.present(SFSafariViewController(url: url))
                            }
                        }

                        return .handled
                    }
                )
                .lineSpacing(0)
                .transition(.opacity)
                .lineLimit(expanded ? nil : 4)
                .foregroundStyle(.secondary)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .id(expanded ? "1" : "0") // removes sliding from animation
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            self.determineTruncation(geometry)
                        }
                        .onChange(of: geometry.size) { _ in
                            guard !expanded else { return }
                            self.determineTruncation(geometry)
                        }
                        // when the text updates, it should re-determine if it was truncated
                        .onChange(of: self.text) { newText in
                            self.determineTruncation(geometry, newText: newText)
                        }
                })

            if truncated && !expanded {
                moreButton
            }
        }
        .animation(.default, value: expanded)
        .frame(maxWidth: .infinity)
        .onPreferenceChange(MoreButtonHeight.self) {
            moreButtonHeight = $0
        }
    }

    var moreButton: some View {
        HStack(spacing: 0) {
            Spacer()

            LinearGradient(
                gradient: Gradient(
                    colors: [
                        Color(UIColor.systemBackground).opacity(0),
                        Color(UIColor.systemBackground)
                    ]
                ),
                startPoint: .leading,
                endPoint: .trailing
            )
            .flipsForRightToLeftLayoutDirection(true)
            .frame(width: 20, height: moreButtonHeight)

            Button(NSLocalizedString("MORE")) {
                expanded.toggle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.system(size: 12))
            .background(Color(UIColor.systemBackground))
            .background(GeometryReader {
                Color.clear.preference(
                    key: MoreButtonHeight.self,
                    value: $0.frame(in: .local).size.height
                )
            })
        }
        .transition(.opacity)
    }

    // determine if text has been truncated
    private func determineTruncation(_ geometry: GeometryProxy, newText: String? = nil) {
        let total = (newText ?? text).boundingRect(
            with: CGSize(
                width: geometry.size.width,
                height: .greatestFiniteMagnitude
            ),
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline)],
            context: nil
        )

        // the line height of the bounding box is slightly different than the actual line height,
        // so we divide by approximately the appropriate line heights
        truncated = total.size.height / 19.6 > geometry.size.height / 18
    }
}

private struct MoreButtonHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value += nextValue()
    }
}

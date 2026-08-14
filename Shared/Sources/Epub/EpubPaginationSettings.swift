//
//  EpubPaginationSettings.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation

/// The readium-css injection and the reading-system variables that drive pagination.
///
/// readium-css specifies the injection order, and it is load-bearing:
///   1. `ReadiumCSS-before.css`, which must precede the author's own styles
///   2. the publication's own stylesheets, or `ReadiumCSS-default.css` when it has none
///   3. `ReadiumCSS-after.css`, which must come last
///
/// Injection happens at document end, so "before" is spliced in as the first child of `<head>`,
/// ahead of the author's `<link>` elements, and "after" is appended.
///
/// Paged mode needs no enabling. `after.css` sets `--RS__colCount` and `--RS__colWidth`
/// unconditionally, and `readium-scroll-on` is the opt-out rather than the opt-in.
///
/// Every value injected here is independent of the size of the viewport. `--RS__viewportWidth` in
/// particular is left at the `100%` readium-css gives it, since it is the width of `:root` and a
/// pixel value measured at load survives a rotation while the `100vw` columns inside it do not:
/// the two then disagree, every page boundary moves off the viewport, and no later measurement
/// puts it right because the width is frozen.
struct EpubPaginationSettings {
    var columnCount: Int = 1

    /// Held at zero so that the scroll offset of a page is exactly `index * viewportWidth`.
    ///
    /// Visual separation comes from `pageGutterPx`, which is padding inside the body. A non-zero
    /// gap makes every page count and every offset gap-aware, and the error accumulates across a
    /// long document, for no benefit the gutter does not already provide.
    var columnGapPx: Int = 0

    var pageGutterPx: Int = 20

    var fontSizePercent: Int = 100

    /// Applies `--USER__fontSize` through `-webkit-text-size-adjust` rather than `zoom`.
    ///
    /// `zoom` scales the whole box, the multi-column geometry included, which corrupts both
    /// `scrollWidth` and the page offsets derived from it. `-webkit-text-size-adjust` scales text
    /// and leaves layout alone. The rule fires only when `--USER__fontSize` is present, and at
    /// 100% neither mechanism does anything, so this changes nothing until font size becomes a
    /// user setting. Its absence at that point would break pagination rather than the font size.
    var applyIOSPatch: Bool = true

    static let `default` = EpubPaginationSettings()

    /// The single script injected into every spine document.
    ///
    /// The viewport element and the stylesheets arrive together rather than as two scripts,
    /// because two would make the order between them significant for no benefit.
    func injectionScript() -> String {
        let before = Self.stylesheet(named: "ReadiumCSS-before")
        let after = Self.stylesheet(named: "ReadiumCSS-after")
        let fallback = Self.stylesheet(named: "ReadiumCSS-default")

        return """
        (function() {
            var head = document.head || document.getElementsByTagName('head')[0];
            if (!head) { return; }

            // ePub XHTML carries no viewport meta element, causing WebKit to lay out at a 980 px
            // desktop viewport. 100vw then resolves to 980 px, a whole document fits in one
            // column, and the page count comes back as 1 with no error of any kind.
            var viewport = head.querySelector('meta[name="viewport"]');
            if (!viewport) {
                viewport = document.createElement('meta');
                viewport.setAttribute('name', 'viewport');
                head.appendChild(viewport);
            }
            // User scaling is disabled because a double tap in the reader's tap zones zooms the
            // document, and a zoomed document no longer shows the page the offsets describe: the
            // reader is left partway between two columns until the next page turn resets it.
            // Scaling is a visual-viewport transform, so it corrupts neither `scrollWidth` nor the
            // counts, only what is on screen, which is why the book survives it. `width` and
            // `initial-scale` are unchanged, so the layout viewport is exactly what it was.
            viewport.setAttribute(
                'content',
                'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no'
            );

            function makeStyle(css) {
                var el = document.createElement('style');
                el.setAttribute('data-aidoku-epub', '1');
                el.textContent = css;
                return el;
            }

            head.insertBefore(makeStyle(\(before)), head.firstChild);

            var authored = head.querySelectorAll(
                'link[rel~="stylesheet"], style:not([data-aidoku-epub])'
            );
            if (authored.length === 0) {
                head.appendChild(makeStyle(\(fallback)));
            }

            head.appendChild(makeStyle(\(after)));

            var root = document.documentElement;
            root.style.setProperty('--RS__colCount', '\(columnCount)');
            root.style.setProperty('--RS__colGap', '\(columnGapPx)px');
            root.style.setProperty('--RS__pageGutter', '\(pageGutterPx)px');
            root.style.setProperty('--USER__fontSize', '\(fontSizePercent)%');

            // readium-css toggles are substring matches against the inline style attribute
            // (`:root[style*="readium-…-on"]`) rather than classes, so `classList.add` does
            // nothing. A flag is activated by setting a custom property whose value is the flag.
            root.style.setProperty('--USER__noOverflow', 'readium-noOverflow-on');
            \(applyIOSPatch ? "root.style.setProperty('--USER__iOSPatch', 'readium-iOSPatch-on');" : "")
        })();
        """
    }

    /// A bundled stylesheet, JSON-encoded so that it embeds in a JavaScript string literal without
    /// regard for quotes, backslashes or newlines.
    ///
    /// The files sit in a `readium-css` directory rather than at the root of the bundle so that
    /// the BSD-3 licence notice stays beside the stylesheets it covers.
    private static func stylesheet(named name: String) -> String {
        guard
            let url = Bundle.main.url(
                forResource: name,
                withExtension: "css",
                subdirectory: "readium-css"
            ),
            let css = try? String(contentsOf: url, encoding: .utf8),
            let encoded = try? JSONEncoder().encode(css),
            let literal = String(data: encoded, encoding: .utf8)
        else {
            LogManager.logger.error("EpubPaginationSettings: missing bundled stylesheet \(name).css")
            assertionFailure("missing bundled stylesheet \(name).css")
            return "\"\""
        }
        return literal
    }
}

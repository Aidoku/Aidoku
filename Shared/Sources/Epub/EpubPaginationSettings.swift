//
//  EpubPaginationSettings.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import UIKit

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

    /// Two columns on an iPad in landscape, one column everywhere else.
    ///
    /// Derived from the viewport rather than from `UIDevice.current.orientation`, which is
    /// `.unknown` until the device has physically moved and so cannot answer at init time.
    static func columnCount(for viewport: CGSize) -> Int {
        UIDevice.current.userInterfaceIdiom == .pad && viewport.width > viewport.height ? 2 : 1
    }

    /// The space between two columns, which is what separates the two pages an iPad shows in
    /// landscape. A gutter alone cannot do that: it pads the body, so it sits outside both columns
    /// rather than between them.
    ///
    /// A page therefore begins every `viewportWidth + columnGapPx` rather than every
    /// `viewportWidth`, and `n` pages span `n * (viewportWidth + gap) - gap`, the last page
    /// carrying no gap after it. Every count and every offset here is written that way; nothing
    /// may divide a scroll offset by the viewport width alone.
    ///
    /// This was held at zero while a page was always one column, to keep that arithmetic trivial.
    /// Two columns is what changed the answer.
    var columnGapPx: Int = 10

    var pageGutterPx: Int = 20

    var fontFamily: String = "System"

    var fontSizePercent: Int = 100

    /// A unitless `line-height` multiple, injected only when set so the publication's own leading
    /// wins by default.
    var lineHeight: Double?

    var paged: Bool = true

    /// Applies `--USER__fontSize` through `-webkit-text-size-adjust` rather than `zoom`.
    ///
    /// `zoom` scales the whole box, the multi-column geometry included, which corrupts both
    /// `scrollWidth` and the page offsets derived from it. `-webkit-text-size-adjust` scales text
    /// and leaves layout alone. The rule fires only when `--USER__fontSize` is present, and at
    /// 100% neither mechanism does anything, so this changes nothing until font size becomes a
    /// user setting. Its absence at that point would break pagination rather than the font size.
    /// For whatever reason Readium made two different settings  for iOS and iPadOS
    var applyIOSPatch: Bool = UIDevice.current.userInterfaceIdiom == .pad ? false : true

    var applyIPadOSPatch: Bool = UIDevice.current.userInterfaceIdiom == .pad ? true : false

    static let `default` = EpubPaginationSettings()

    /// The text readers' settings, mapped onto readium-css user variables, so an epub follows the
    /// same reader settings the text readers already follow. `viewport` decides the column count;
    /// pass the reader's size.
    static func fromUserDefaults(for viewport: CGSize) -> EpubPaginationSettings {
        var settings = EpubPaginationSettings()
        settings.columnCount = columnCount(for: viewport)
        let defaults = UserDefaults.standard
        if let family = defaults.string(forKey: "Reader.textFontFamily") {
            // "System" is the SF font the text readers use for that value
            settings.fontFamily = family == "System" ? "-apple-system" : family
        }
        // the text readers store points; readium-css takes a percentage of the css 16px default
        let fontSize = defaults.object(forKey: "Reader.textFontSize") as? Double ?? 18
        settings.fontSizePercent = Int((fontSize / 16 * 100).rounded())
        // points between lines become a unitless line-height multiple of the font size
        let lineSpacing = defaults.object(forKey: "Reader.textLineSpacing") as? Double ?? 8
        settings.lineHeight = ((fontSize + lineSpacing) / fontSize * 100).rounded() / 100
        let padding = defaults.object(forKey: "Reader.textHorizontalPadding") as? Double ?? 24
        settings.pageGutterPx = Int(padding)
        // In readium's scroll mode a document is one column of natural height, read by scrolling
        // vertically; the renderer counts its pages in viewport heights instead of columns.
        settings.paged = defaults.string(forKey: "Reader.epubReaderStyle") != "scroll"
        return settings
    }

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
            root.style.setProperty('--USER__colCount', '\(columnCount)');
            root.style.setProperty('--RS__colGap', '\(columnGapPx)px');
            root.style.setProperty('--RS__pageGutter', '\(pageGutterPx)px');
            root.style.setProperty('--USER__fontFamily', \(Self.jsLiteral(fontFamily)));
            root.style.setProperty('--USER__fontSize', '\(fontSizePercent)%');
            \(lineHeight.map { "root.style.setProperty('--USER__lineHeight', '\($0)');" } ?? "")
            \(paged ? "root.style.setProperty('--USER__View', 'readium-paged-on');" : "root.style.setProperty('--USER__View', 'readium-scroll-on');")
            root.style.setProperty('color-scheme', 'light dark');
            root.style.setProperty('--USER__backgroundColor', 'light-dark(#FFFFFF, #000000)');
            root.style.setProperty('--USER__textColor', 'light-dark(#000000, #FFFFFF)');

            // readium-css toggles are substring matches against the inline style attribute
            // (`:root[style*="readium-…-on"]`) rather than classes, so `classList.add` does
            // nothing. A flag is activated by setting a custom property whose value is the flag.
            //
            // This one reads as a double negative and is worth stating outright: every rule it
            // gates is written `:not([style*="readium-noOverflow-on"])`, six of them and no
            // positive selector, so **setting** it removes readium-css's `overflow: hidden` and
            // `overflow: clip` from `body` and `:root`.
            //
            // Kept deliberately. Measured on Project Gutenberg 20871, whose tables run to 450px in
            // a 280px column: clipping changes neither `scrollWidth` nor the page count, so it
            // hides content the column has already lost rather than making it reachable. Cutting a
            // table at the column edge leaves nothing to show for it, while content that bleeds
            // onto the following pages is at least visible, and the table pass below scales the
            // tables that would do it. Removing this line breaks no test, so it is not load-bearing
            // for pagination; it is a choice about which failure a reader is better served by.
            //
            // Tracked upstream at readium/readium-css#138, where the clipping these rules apply was
            // added deliberately for this complaint and gated so a reading system handling overflow
            // itself can opt out, which is what setting this does. Worth reading before changing it.
            root.style.setProperty('--USER__noOverflow', 'readium-noOverflow-on');
            \(applyIOSPatch ? "root.style.setProperty('--USER__iOSPatch', 'readium-iOSPatch-on');" : "")
            \(applyIPadOSPatch ? "root.style.setProperty('--USER__iPadOSPatch', 'readium-iPadOSPatch-on');" : "")

            // A table wider than its column would paint across the page boundary onto the
            // following pages, since noOverflow disables readium-css's body clipping. Each one is
            // scaled down to fit a single page whole instead, and marked so a tap on it can open
            // the reader's fullscreen table preview. `transform` shrinks only the painting, so a
            // wrapper carries the scaled height for the column layout and clips whatever the
            // transform did not cover. Measured after the stylesheets and the variables above,
            // which is what decides the column geometry the tables must fit.
            var tables = Array.prototype.slice.call(document.querySelectorAll('table'))
                .filter(function(table) {
                    // a nested table is part of its outer table's width
                    return !(table.parentElement && table.parentElement.closest('table'));
                });
            tables.forEach(function(table) {
                var wrap = document.createElement('div');
                table.parentNode.insertBefore(wrap, table);
                wrap.appendChild(table);
                var avail = wrap.clientWidth;
                var width = table.offsetWidth;
                var height = table.offsetHeight;
                if (width <= avail || avail <= 0 || height <= 0) {
                    // the table fits where it is; put it back untouched
                    wrap.parentNode.insertBefore(table, wrap);
                    wrap.parentNode.removeChild(wrap);
                    return;
                }
                // In paged mode the whole table must land on one page, so the scale also fits
                // the column height; scrolled documents only need the width.
                var availHeight = \(paged ? "window.innerHeight * 0.95" : "Infinity");
                var scale = Math.min(avail / width, availHeight / height);
                table.style.transform = 'scale(' + scale + ')';
                table.style.transformOrigin = 'top left';
                table.style.margin = '0';
                wrap.style.height = (height * scale) + 'px';
                wrap.style.overflow = 'hidden';
                wrap.style.breakInside = 'avoid';
                wrap.setAttribute('data-aidoku-table', '1');
            });
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
            let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            LogManager.logger.error("EpubPaginationSettings: missing bundled stylesheet \(name).css")
            assertionFailure("missing bundled stylesheet \(name).css")
            return "\"\""
        }
        return jsLiteral(css)
    }

    /// A JavaScript string literal, quotes included, for a value that is not ours to choose.
    ///
    /// `Reader.textFontFamily` is picked from `UIFont.familyNames`, which includes families the
    /// user has installed, so a name carrying an apostrophe would close the literal early and make
    /// the whole injected script a syntax error. That failure is silent: no viewport element, no
    /// readium-css, and a page count measured against a 980px layout that looks plausible.
    private static func jsLiteral(_ value: String) -> String {
        guard
            let encoded = try? JSONEncoder().encode(value),
            let literal = String(data: encoded, encoding: .utf8)
        else {
            return "\"\""
        }
        return literal
    }
}

//
//  EpubPaginationSettings.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import UIKit

// readium-css fixes the injection order and it is load-bearing: before.css, the publication's own
// stylesheets or default.css, then after.css. every injected value is viewport-independent;
// --RS__viewportWidth stays at 100%, a pixel value surviving a rotation the 100vw columns do not
struct EpubPaginationSettings: Equatable {
    var columnCount: Int = 1

    // UIDevice.current.orientation is .unknown until the device moves, so it cannot answer here
    static func columnCount(for viewport: CGSize) -> Int {
        UIDevice.current.userInterfaceIdiom == .pad && viewport.width > viewport.height ? 2 : 1
    }

    // a page begins every viewportWidth + columnGapPx, so nothing may divide a scroll offset by
    // the viewport width alone
    var columnGapPx: Int = 10

    var pageGutterPx: Int = 20

    var fontFamily: String = "System"

    var fontSizePercent: Int = 100

    var lineHeight: Double?

    var paged: Bool = true

    // scroll style passes content under the bars, so the clearance is padding inside the document
    var scrollPaddingTopPx: Int = 0

    var scrollPaddingBottomPx: Int = 0

    var scrollPaddingLeftPx: Int = 0

    var scrollPaddingRightPx: Int = 0

    mutating func applyScrollClearance(_ clearance: UIEdgeInsets) {
        guard !paged else { return }
        scrollPaddingTopPx = Int(clearance.top)
        scrollPaddingBottomPx = Int(clearance.bottom)
        scrollPaddingLeftPx = Int(clearance.left)
        scrollPaddingRightPx = Int(clearance.right)
    }

    // -webkit-text-size-adjust rather than zoom, which would scale the column geometry too
    var applyIOSPatch: Bool = UIDevice.current.userInterfaceIdiom == .pad ? false : true

    var applyIPadOSPatch: Bool = UIDevice.current.userInterfaceIdiom == .pad ? true : false

    static let `default` = EpubPaginationSettings()

    // the text readers' settings mapped onto readium-css variables; viewport is the reader's size
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
        // scroll mode is one column of natural height, counted in viewport heights
        settings.paged = defaults.string(forKey: "Reader.textReaderStyle") != "scroll"
        return settings
    }

    func injectionScript() -> String {
        let before = Self.stylesheet(named: "ReadiumCSS-before")
        let after = Self.stylesheet(named: "ReadiumCSS-after")
        let fallback = Self.stylesheet(named: "ReadiumCSS-default")

        return """
        (function() {
            var head = document.head || document.getElementsByTagName('head')[0];
            if (!head) { return; }

            // without this, WebKit lays out at a 980px desktop viewport and reports 1 page
            var viewport = head.querySelector('meta[name="viewport"]');
            if (!viewport) {
                viewport = document.createElement('meta');
                viewport.setAttribute('name', 'viewport');
                head.appendChild(viewport);
            }
            // scaling off: a double tap in the tap zones would zoom the page off its own offsets
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
            head.appendChild(makeStyle(
                'a, a:visited { color: #FF2D55; }' +
                '@media (prefers-color-scheme: dark) { a, a:visited { color: #FF375F; } }' +
                'a:active { opacity: 0.7; }'
            ));

            var root = document.documentElement;
            root.style.setProperty('--USER__colCount', '\(columnCount)');
            root.style.setProperty('--RS__colGap', '\(columnGapPx)px');
            root.style.setProperty('--RS__pageGutter', '\(pageGutterPx)px');
            \(scrollPaddingTopPx > 0
                ? "root.style.setProperty('--RS__scrollPaddingTop', '\(scrollPaddingTopPx)px');"
                : "")
            \(scrollPaddingBottomPx > 0
                ? "root.style.setProperty('--RS__scrollPaddingBottom', '\(scrollPaddingBottomPx)px');"
                : "")
            \(scrollPaddingLeftPx > 0
                ? "root.style.setProperty('--RS__scrollPaddingLeft', '\(scrollPaddingLeftPx)px');"
                : "")
            \(scrollPaddingRightPx > 0
                ? "root.style.setProperty('--RS__scrollPaddingRight', '\(scrollPaddingRightPx)px');"
                : "")
            root.style.setProperty('--USER__fontFamily', \(Self.jsLiteral(fontFamily)));
            root.style.setProperty('--USER__fontSize', '\(fontSizePercent)%');
            \(lineHeight.map { "root.style.setProperty('--USER__lineHeight', '\($0)');" } ?? "")
            \(paged ? "root.style.setProperty('--USER__View', 'readium-paged-on');" : "root.style.setProperty('--USER__View', 'readium-scroll-on');")
            root.style.setProperty('color-scheme', 'light dark');
            root.style.setProperty('--USER__backgroundColor', 'light-dark(#FFFFFF, #000000)');
            root.style.setProperty('--USER__textColor', 'light-dark(#000000, #FFFFFF)');
            // the app tint, systemPink in both appearances
            root.style.setProperty('--USER__linkColor', 'light-dark(#FF2D55, #FF375F)');

            // readium-css flags are substring matches on the style attribute, so a flag is set by
            // giving a property its name. this one is a double negative: setting it REMOVES the
            // overflow clipping, so a wide table bleeds rather than being cut. readium-css#138
            root.style.setProperty('--USER__noOverflow', 'readium-noOverflow-on');
            \(applyIOSPatch ? "root.style.setProperty('--USER__iOSPatch', 'readium-iOSPatch-on');" : "")
            \(applyIPadOSPatch ? "root.style.setProperty('--USER__iPadOSPatch', 'readium-iPadOSPatch-on');" : "")

            // scaled to one page and marked for the preview; transform shrinks only the painting,
            // so the wrapper carries the height
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
                // paged tables must fit the column height too; scrolled ones only the width
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

    // kept in a directory so the BSD-3 licence notice stays beside the stylesheets it covers
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

    // an apostrophe in a font family would close the literal and break the whole script, silently
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

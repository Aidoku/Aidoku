//
//  EpubPaginationSettings.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import UIKit

// readium-css specifies the injection order and it is load-bearing: before.css, the publication's
// own stylesheets or default.css where it has none, then after.css. every value injected is
// independent of the viewport size, --RS__viewportWidth included, which is left at 100% because a
// pixel value measured at load survives a rotation while the 100vw columns inside it do not
struct EpubPaginationSettings {
    var columnCount: Int = 1

    // derived from the viewport rather than UIDevice.current.orientation, which is .unknown until
    // the device has physically moved and so cannot answer at init time
    static func columnCount(for viewport: CGSize) -> Int {
        UIDevice.current.userInterfaceIdiom == .pad && viewport.width > viewport.height ? 2 : 1
    }

    // separates the two pages an iPad shows in landscape, which a gutter cannot do since it pads
    // the body. a page therefore begins every viewportWidth + columnGapPx, so nothing may divide a
    // scroll offset by the viewport width alone
    var columnGapPx: Int = 10

    var pageGutterPx: Int = 20

    var fontFamily: String = "System"

    var fontSizePercent: Int = 100

    // injected only when set, so the publication's own leading wins by default
    var lineHeight: Double?

    var paged: Bool = true

    // applies --USER__fontSize through -webkit-text-size-adjust rather than zoom, which would scale
    // the multi-column geometry too and corrupt both scrollWidth and the offsets derived from it.
    // readium splits the patch into separate iOS and iPadOS settings
    var applyIOSPatch: Bool = UIDevice.current.userInterfaceIdiom == .pad ? false : true

    var applyIPadOSPatch: Bool = UIDevice.current.userInterfaceIdiom == .pad ? true : false

    static let `default` = EpubPaginationSettings()

    // the text readers' settings mapped onto readium-css user variables, so an epub follows the
    // reader settings they already follow. pass the reader's size as the viewport
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
        // in readium's scroll mode a document is one column of natural height, and the renderer
        // counts its pages in viewport heights instead of columns
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

            // epub xhtml carries no viewport meta element, so WebKit lays out at a 980px desktop
            // viewport, a whole document fits one column, and the count comes back as 1 with no
            // error of any kind
            var viewport = head.querySelector('meta[name="viewport"]');
            if (!viewport) {
                viewport = document.createElement('meta');
                viewport.setAttribute('name', 'viewport');
                head.appendChild(viewport);
            }
            // user scaling is off because a double tap in the reader's tap zones zooms the
            // document, which then no longer shows the page the offsets describe and leaves the
            // reader partway between two columns until the next turn resets it
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

            // readium-css toggles are substring matches against the inline style attribute, so a
            // flag is set by giving a custom property its name. this one is a double negative:
            // setting it removes readium-css's overflow clipping, trading a table cut off at the
            // column edge for one that bleeds, which the table pass below scales. see
            // readium/readium-css#138 before changing it
            root.style.setProperty('--USER__noOverflow', 'readium-noOverflow-on');
            \(applyIOSPatch ? "root.style.setProperty('--USER__iOSPatch', 'readium-iOSPatch-on');" : "")
            \(applyIPadOSPatch ? "root.style.setProperty('--USER__iPadOSPatch', 'readium-iPadOSPatch-on');" : "")

            // scaled to fit one page whole and marked so a tap can open the fullscreen preview.
            // transform shrinks only the painting, so a wrapper carries the scaled height
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
                // in paged mode the whole table must land on one page, so the scale fits the
                // column height too; scrolled documents only need the width
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

    // the files sit in a readium-css directory rather than at the bundle root so the BSD-3 licence
    // notice stays beside the stylesheets it covers
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

    // a font family carrying an apostrophe would close the literal early and make the whole script
    // a syntax error, silently: no viewport element, no readium-css, a plausible 980px page count
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

//
//  EpubWebViewFactory.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import WebKit

/// Builds the locked-down `WKWebView` configuration that ePub content renders into.
///
/// Every resource is served by `EpubSchemeHandler` rather than by the disk or the network:
///   - JavaScript belonging to the page is disabled
///   - a content rule list blocks every http and https load, so a tracking pixel embedded in a
///     book cannot fire; subresource loads bypass the navigation policy delegate, which is why a
///     rule list is required rather than a delegate check alone
///   - the data store is non-persistent, so nothing the book does is written to the container
///
/// A scheme handler cannot be replaced once a configuration is built, so a configuration belongs
/// to one provider and therefore to one book.
@MainActor
enum EpubWebViewFactory {
    /// The world our own injected scripts run in. It is unaffected by
    /// `allowsContentJavaScript = false`, which disables only scripts belonging to the page.
    static let contentWorld = WKContentWorld.world(name: "aidoku-epub")

    /// Compiling the content rule list is asynchronous, so building a configuration is too.
    static func makeConfiguration(provider: any EpubResourceProvider) async -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(
            EpubSchemeHandler(provider: provider),
            forURLScheme: EpubSchemeHandler.scheme
        )

        if let ruleList = await makeRemoteBlockingRuleList() {
            configuration.userContentController.add(ruleList)
        }
        configuration.userContentController.addUserScript(makeViewportScript())

        return configuration
    }

    /// Blocks every http and https load. Requests carrying a custom scheme never reach the
    /// content blocker, so resources belonging to the book are unaffected, while a remote image,
    /// font or stylesheet is stopped before it leaves the device.
    private static func makeRemoteBlockingRuleList() async -> WKContentRuleList? {
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """
        do {
            return try await WKContentRuleListStore.default()?.compileContentRuleList(
                forIdentifier: "aidoku-epub-block-remote",
                encodedContentRuleList: rules
            )
        } catch {
            LogManager.logger.error("EpubWebViewFactory: failed to compile content rule list: \(error)")
            return nil
        }
    }

    /// ePub XHTML carries no viewport meta element, causing WebKit to lay out at a 980 px desktop
    /// viewport. Consequently the content renders at an unusable scale and every width
    /// measurement is wrong. Omitting the injection produces no error of any kind.
    private static func makeViewportScript() -> WKUserScript {
        let source = """
        (function() {
            var head = document.head || document.getElementsByTagName('head')[0];
            if (!head) { return; }
            var viewport = head.querySelector('meta[name="viewport"]');
            if (!viewport) {
                viewport = document.createElement('meta');
                viewport.setAttribute('name', 'viewport');
                head.appendChild(viewport);
            }
            viewport.setAttribute('content', 'width=device-width, initial-scale=1');
        })();
        """
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: contentWorld
        )
    }
}

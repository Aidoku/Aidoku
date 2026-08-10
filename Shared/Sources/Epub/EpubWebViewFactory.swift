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
    static func makeConfiguration(
        provider: any EpubResourceProvider,
        settings: EpubPaginationSettings = .default
    ) async -> WKWebViewConfiguration {
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
        configuration.userContentController.addUserScript(makeInjectionScript(settings: settings))

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

    /// The viewport element, the readium-css stylesheets and the reading-system variables, as one
    /// script. `EpubPaginationSettings` owns its contents; see the injection order recorded there.
    ///
    /// It runs in `contentWorld`, so `allowsContentJavaScript = false` continues to hold for
    /// scripts belonging to the book. Omitting any part of this injection produces no error of any
    /// kind, only a document laid out at 980 px reporting a plausible and wrong page count.
    private static func makeInjectionScript(settings: EpubPaginationSettings) -> WKUserScript {
        WKUserScript(
            source: settings.injectionScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: contentWorld
        )
    }
}

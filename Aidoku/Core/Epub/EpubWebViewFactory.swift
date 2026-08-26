//
//  EpubWebViewFactory.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import WebKit

// a scheme handler cannot be replaced once built, so a configuration belongs to one book
@MainActor
enum EpubWebViewFactory {
    enum ConfigurationError: Error {
        case remoteBlockingUnavailable((any Error)?)
    }

    // unaffected by allowsContentJavaScript = false, which disables only the page's own scripts
    static let contentWorld = WKContentWorld.world(name: "aidoku-epub")

    // throws rather than returning a configuration without the rule list: a subresource load never
    // reaches the navigation policy delegate, so the list is all that stands between book and network
    static func makeConfiguration(
        provider: any EpubResourceProvider,
        settings: EpubPaginationSettings = .default
    ) async throws -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(
            EpubSchemeHandler(provider: provider),
            forURLScheme: EpubSchemeHandler.scheme
        )

        configuration.userContentController.add(try await makeRemoteBlockingRuleList())
        configuration.userContentController.addUserScript(makeInjectionScript(settings: settings))

        return configuration
    }

    // a custom scheme never reaches the content blocker, so the book's own resources still load
    private static func makeRemoteBlockingRuleList() async throws -> WKContentRuleList {
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """
        guard let store = WKContentRuleListStore.default() else {
            LogManager.logger.error("EpubWebViewFactory: no content rule list store is available")
            throw ConfigurationError.remoteBlockingUnavailable(nil)
        }

        let compiled: WKContentRuleList?
        do {
            compiled = try await store.compileContentRuleList(
                forIdentifier: "aidoku-epub-block-remote",
                encodedContentRuleList: rules
            )
        } catch {
            LogManager.logger.error("EpubWebViewFactory: failed to compile content rule list: \(error)")
            throw ConfigurationError.remoteBlockingUnavailable(error)
        }

        guard let compiled else {
            LogManager.logger.error("EpubWebViewFactory: the content rule list compiled to nothing")
            throw ConfigurationError.remoteBlockingUnavailable(nil)
        }
        return compiled
    }

    // omitting any part of this errors nowhere, it just reports a plausible and wrong page count
    static func makeInjectionScript(settings: EpubPaginationSettings) -> WKUserScript {
        WKUserScript(
            source: settings.injectionScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: contentWorld
        )
    }
}

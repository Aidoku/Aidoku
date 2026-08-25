//
//  EpubWebViewFactory.swift
//  Aidoku
//
//  Created by Pietro Baiguini on 8/10/26.
//

import Foundation
import WebKit

// a scheme handler cannot be replaced once a configuration is built, so a configuration belongs to
// one provider and therefore to one book
@MainActor
enum EpubWebViewFactory {
    enum ConfigurationError: Error {
        case remoteBlockingUnavailable((any Error)?)
    }

    // our own scripts run here, unaffected by allowsContentJavaScript = false, which disables only
    // scripts belonging to the page
    static let contentWorld = WKContentWorld.world(name: "aidoku-epub")

    // throws rather than returning a configuration the rule list is missing from: a subresource
    // load never reaches the navigation policy delegate, so the rule list is the only thing left
    // between a book and the network, and without it a tracking pixel fires with the reader's ip
    // while the page renders exactly as it would have done
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

    // requests carrying a custom scheme never reach the content blocker, so the book's own
    // resources are unaffected while a remote image, font or stylesheet is stopped
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

    // omitting any part of this injection produces no error of any kind, only a document laid out
    // at 980px reporting a plausible and wrong page count
    private static func makeInjectionScript(settings: EpubPaginationSettings) -> WKUserScript {
        WKUserScript(
            source: settings.injectionScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: contentWorld
        )
    }
}

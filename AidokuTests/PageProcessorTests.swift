//
//  PageProcessorTests.swift
//  Aidoku
//
//  Created by skitty on 8/21/26.
//

@testable import Aidoku
import AidokuRunner
import Foundation
import Nuke
import Testing

@Suite(.serialized)
struct PageInterceptorProcessorTests {
    @Test("Nuke fetches shared page data once but processes context separately")
    func testNukeCaching() async throws {
        PageProcessorURLProtocol.reset()

        let dataLoader = DataLoader(configuration: {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [PageProcessorURLProtocol.self]
            config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            return config
        }())
        let pipeline = ImagePipeline(configuration: {
            var config = ImagePipeline.Configuration()
            config.dataLoader = dataLoader
            config.dataCache = nil
            config.imageCache = ImageCache()
            return config
        }())

        let runner = TestableSourceRunner()
        let source = AidokuRunner.Source.test(runner: runner)

        let url = try #require(URL(string: "https://page-processor-test/image.png"))

        let firstContext: PageContext = ["slice": "1"]
        let secondContext: PageContext = ["slice": "2"]

        func makeRequest(context: PageContext) -> ImageRequest {
            ImageRequest(
                urlRequest: URLRequest(url: url),
                processors: [PageInterceptorProcessor(source: source, pageContext: context)],
                userInfo: [.processesKey: true]
            )
        }

        let firstRequest = makeRequest(context: firstContext)
        let secondRequest = makeRequest(context: secondContext)

        async let firstResult = pipeline.image(for: firstRequest)
        async let secondResult = pipeline.image(for: secondRequest)
        _ = try await (firstResult, secondResult)

        // it should only make one request for the shared data
        #expect(PageProcessorURLProtocol.requestCount == 1)

        // it should process contexts separately
        let processedContexts = Set(await runner.storage.getContexts())
        #expect(processedContexts == Set([firstContext, secondContext]))

        // now make sure it doesn't make any requests and doesn't process again if we retry
        _ = try await pipeline.image(for: firstRequest)
        _ = try await pipeline.image(for: secondRequest)
        #expect(PageProcessorURLProtocol.requestCount == 1)
        #expect(await runner.storage.getContexts().count == 2)
    }
}

// fake image data provider without networking
private class PageProcessorURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _requestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestCount
    }

    static func reset() {
        lock.lock()
        _requestCount = 0
        lock.unlock()
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "page-processor-test"
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self._requestCount += 1
        Self.lock.unlock()

        // https://gist.github.com/ondrek/7413434
        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: imageData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

//
//  PageInterceptorProcessor.swift
//  Aidoku
//
//  Created by Skitty on 5/8/25.
//

import AidokuRunner
import Foundation
import Nuke

extension ImageRequest.UserInfoKey {
    static let contextKey: Self = "aidoku/context"
    static let processesKey: Self = "aidoku/usesPageProcessor"
}

struct PageInterceptorProcessor: ImageProcessing {
    let identifier: String = "pageProcessor"

    let source: AidokuRunner.Source

    func process(_ image: PlatformImage) -> PlatformImage? {
        nil
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        let pageContext = context.request.userInfo[.contextKey] as? PageContext

        // image processing should be async so we don't have to block, but Nuke doesn't support this...
        // this isn't run on the main thread anyways, so appears to be fine for now
        let output: AidokuRunner.PlatformImage? = try BlockingThrowingTask {
            guard let request = context.request.urlRequest else {
                return nil
            }

            let urlResponse = context.response.urlResponse as? HTTPURLResponse
            let code = urlResponse?.statusCode ?? 200
            let headers = urlResponse?.allHeaderFields

            func toStringMap<K, V>(_ dict: [K: V]) -> [String: String] {
                dict
                    .compactMapKeys { $0 as? String }
                    .compactMapValues { $0 as? String }
            }

            let imageDescriptor = if container.image.size == .zero, let data = container.data {
                if let image = PlatformImage(data: data) {
                    try await source.store(value: image)
                } else {
                    try await source.store(value: data)
                }
            } else {
                try await source.store(value: container.image)
            }

            let response = Response(
                code: code,
                headers: toStringMap(headers ?? [:]),
                request: .init(
                    url: request.url,
                    headers: toStringMap(request.allHTTPHeaderFields ?? [:])
                ),
                image: imageDescriptor
            )

            let result = try await source.processPageImage(response: response, context: pageContext)

            try await source.remove(value: imageDescriptor)

            return result
        }.get()

        var container = container
        container.image = output?.image
            ?? container.data.flatMap { PlatformImage(data: $0) }
            ?? container.image
        return container
    }

    func processWithoutImage(request: ImageRequest) throws -> ImageContainer {
        let container = ImageContainer(image: .mangaPlaceholder)
        let context = ImageProcessingContext(
            request: request,
            response: .init(
                container: container,
                request: request,
                urlResponse: (request.url ?? request.urlRequest?.url).flatMap {
                    HTTPURLResponse(
                        url: $0,
                        statusCode: 404,
                        httpVersion: nil,
                        headerFields: nil
                    )
                }
            ),
            isCompleted: true
        )
        return try self.process(container, context: context)
    }
}

private extension Dictionary {
    func compactMapKeys<T>(_ transform: ((Key) throws -> T?)) rethrows -> [T: Value] {
        try self.reduce(into: [T: Value]()) { result, x in
            if let key = try transform(x.key) {
                result[key] = x.value
            }
        }
    }
}

//
//  SourceImageView.swift
//  Aidoku
//
//  Created by Skitty on 4/26/25.
//

import AidokuRunner
import NukeUI
import SwiftUI

struct SourceImageView: View {
    var source: AidokuRunner.Source?

    let imageUrl: String
    var width: CGFloat?
    var height: CGFloat?
    var downsampleWidth: CGFloat?
    var contentMode: ContentMode = .fill
    var placeholder = "MangaPlaceholder"

    @State private var imageRequest: ImageRequest?

    var body: some View {
        LazyImage(
            request: imageRequest,
            transaction: .init(animation: .default)
        ) { state in
            let result = if let image = state.image {
                image
            } else {
                Image(placeholder)
            }
            result
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: width, height: height)
                .id(state.image != nil ? imageUrl : "placeholder") // ensures only opacity is animated
        }
        .processors({
            if let downsampleWidth {
                [DownsampleProcessor(width: downsampleWidth)]
            } else {
                []
            }
        }())
        .onAppear {
            guard imageRequest == nil else { return }
            Task {
                await loadImageRequest(url: imageUrl)
            }
        }
        .onChange(of: imageUrl) { newValue in
            imageRequest = nil
            Task {
                await loadImageRequest(url: newValue)
            }
        }
    }

    func loadImageRequest(url: String) async {
        defer {
            if imageRequest == nil {
                imageRequest = ImageRequest(url: URL(string: url))
            }
        }
        guard let source else {
            return
        }
        if source.features.providesImageRequests {
            do {
                imageRequest = ImageRequest(urlRequest: try await source.getImageRequest(url: url, context: nil))
            } catch {
                LogManager.logger.error("Failed to load source image: \(error.localizedDescription)")
            }
        }
    }
}

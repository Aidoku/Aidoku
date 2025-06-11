//
//  CoverView.swift
//  Aidoku
//
//  Created by Skitty on 9/25/23.
//

import AidokuRunner
import Nuke
import NukeUI
import SwiftUI

struct MangaCoverPageView: View {
    let source: AidokuRunner.Source?
    let manga: AidokuRunner.Manga
    let coverImage: String

    @State private var alternateCovers: [String] = []
    @State private var error: Error?

    @EnvironmentObject private var path: NavigationCoordinator

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PlatformNavigationStack {
            TabView {
                view(coverImage: coverImage)
                if let error {
                    ErrorView(error: error) {
                        await loadCovers()
                    }
                } else {
                    ForEach(alternateCovers, id: \.self) { cover in
                        if cover != coverImage {
                            view(coverImage: cover)
                        }
                    }
                }
            }
            .tabViewStyle(.page)
            .navigationTitle(NSLocalizedString("COVER"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("DONE")).bold()
                    }
                }
            }
            .task {
                await loadCovers()
            }
        }
    }

    func loadCovers() async {
        guard let source, source.features.providesAlternateCovers else { return }
        withAnimation {
            error = nil
        }
        do {
            alternateCovers = try await source.getAlternateCovers(manga: manga)
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }

    func view(coverImage: String) -> some View {
            VStack(alignment: .center) {
                Spacer()
                MangaCoverView(source: source, coverImage: coverImage, contentMode: .fit)
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .contextMenu {
                        if let url = URL(string: coverImage) {
                            Button {
                                if let viewController = UIApplication.shared.firstKeyWindow?.rootViewController {
                                    Task {
                                        let image = try await loadImage(url: url)
                                        image.saveToAlbum(viewController: viewController)
                                    }
                                }
                            } label: {
                                Label(NSLocalizedString("SAVE_TO_PHOTOS"), systemImage: "photo")
                            }
                            // todo: share sheet doesn't work on ipads
//                            Button {
//                                Task {
//                                    let image = try await loadImage(url: url)
//                                    showShareSheet(image: image)
//                                }
//                            } label: {
//                                Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
//                            }
                        }
                    }
                    .padding(16)
                Spacer()
            }
    }

    func loadImage(url: URL) async throws -> UIImage {
        try await ImagePipeline.shared.image(for: url)
    }
}

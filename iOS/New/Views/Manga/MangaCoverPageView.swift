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
    @State var manga: AidokuRunner.Manga
    @State var inLibrary: Bool?

    @State private var hasEditedCover = false
    @State private var alternateCovers: [String] = []
    @State private var error: Error?

    @State private var showImagePicker = false
    @State private var uploadedCover: UIImage?

    @Environment(\.dismiss) private var dismiss

    init(source: AidokuRunner.Source?, manga: AidokuRunner.Manga, inLibrary: Bool? = nil) {
        self.source = source
        self._manga = State(initialValue: manga)
        self._inLibrary = State(initialValue: inLibrary)

        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(.primary)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(.secondary)
    }

    var body: some View {
        PlatformNavigationStack {
            VStack {
                TabView {
                    view(coverImage: manga.cover ?? "")
                    if let error {
                        ErrorView(error: error) {
                            await loadCovers()
                        }
                    } else {
                        ForEach(alternateCovers, id: \.self) { cover in
                            if cover != manga.cover {
                                view(coverImage: cover)
                            }
                        }
                    }
                }
                .tabViewStyle(.page)

                if inLibrary == true || manga.isLocal() {
                    HStack {
                        Button {
                            showImagePicker = true
                        } label: {
                            Text(NSLocalizedString("UPLOAD_CUSTOM_COVER"))
                        }
                        .buttonStyle(.bordered)

                        if source != nil && hasEditedCover && !manga.isLocal() {
                            Button {
                                Task {
                                    let newUrl = await MangaManager.shared.resetCover(manga: manga)
                                    if let newUrl {
                                        setCover(url: newUrl, original: true)
                                    }
                                }
                            } label: {
                                Text(NSLocalizedString("RESET_COVER"))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground)) // ios 26 has no background color
            .navigationTitle(NSLocalizedString("COVER"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $uploadedCover)
                    .ignoresSafeArea()
            }
            .onChange(of: uploadedCover) { newImage in
                guard let newImage else { return }

                Task {
                    let newUrl = await MangaManager.shared.setCover(
                        manga: manga,
                        cover: newImage
                    )
                    if let newUrl {
                        setCover(url: newUrl)
                    }
                }
            }
            .task {
                await CoreDataManager.shared.container.performBackgroundTask { context in
                    hasEditedCover = CoreDataManager.shared.hasEditedKey(
                        sourceId: manga.sourceKey,
                        mangaId: manga.key,
                        key: .cover,
                        context: context
                    )
                    if inLibrary == nil {
                        inLibrary = CoreDataManager.shared.hasLibraryManga(
                            sourceId: manga.sourceKey,
                            mangaId: manga.key,
                            context: context
                        )
                    }
                }
                await loadCovers()
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
                        if coverImage != manga.cover {
                            Button {
                                Task {
                                    await CoreDataManager.shared.setCover(
                                        sourceId: manga.sourceKey,
                                        mangaId: manga.key,
                                        coverUrl: coverImage
                                    )
                                    setCover(url: coverImage)
                                }
                            } label: {
                                Label(NSLocalizedString("SET_COVER_IMAGE"), systemImage: "book.closed")
                            }
                        }
                        // todo: share sheet doesn't work on ipads
//                        Button {
//                            Task {
//                                let image = try await loadImage(url: url)
//                                showShareSheet(image: image)
//                            }
//                        } label: {
//                            Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
//                        }
                    }
                }
                .padding(16)
            Spacer()
        }
    }

    func loadCovers() async {
        guard let source, source.features.providesAlternateCovers else { return }
        withAnimation {
            error = nil
        }
        do {
            let result = try await source.getAlternateCovers(manga: manga)
            alternateCovers = result.unique()
        } catch {
            withAnimation {
                self.error = error
            }
        }
    }

    func loadImage(url: URL) async throws -> UIImage {
        try await ImagePipeline.shared.image(for: url)
    }

    func setCover(url: String, original: Bool = false) {
        if manga.cover == url {
            // make the image view refresh with a unique url
            manga.cover = url + "?edited=\(Date().timeIntervalSince1970)"
        } else {
            manga.cover = url
        }
        withAnimation {
            hasEditedCover = !original
        }
        NotificationCenter.default.post(name: .updateMangaDetails, object: manga)
    }
}

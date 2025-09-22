//
//  LocalFileImportView.swift
//  Aidoku
//
//  Created by Skitty on 6/6/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct LocalFileImportView: View {
    private let fileInfo: ImportFileInfo?

    @State private var fullyPresented = false

    init(fileInfo: ImportFileInfo? = nil) {
        if let fileInfo {
            self.fileInfo = fileInfo
            self._fullyPresented = State(initialValue: true)
        } else {
            self.fileInfo = nil
            self._fullyPresented = State(initialValue: false)
        }
    }

    var body: some View {
        let contentView = ContentView(fileInfo: fileInfo, fullyPresented: $fullyPresented)
        if #available(iOS 16.0, *) {
            PresentationDetentHandler(fullyPresented: $fullyPresented) {
                contentView
            }
        } else {
            contentView
        }
    }
}

extension LocalFileImportView {
    struct ContentView: View {
        @Binding var fullyPresented: Bool

        @State private var fileInfo: ImportFileInfo?

        // MARK: Configuration Fields
        @State private var name: String = ""
        @State private var volume: Float?
        @State private var chapter: Float? = 1

        @State private var coverImage: PlatformImage?
        @State private var seriesName: String = ""
        @State private var seriesDescription: String = ""

        @State private var selectedMangaId: String = ""
        @State private var selectedMangaTitle: String = ""

        // MARK: Validation
        @State private var nameEmpty = false
        @State private var volumeChapterEmpty = false
        @State private var nameValid = true
        @State private var volumeChapterValid = true

        // MARK: Presentation Bindings
        @State private var hasLoaded = false
        @State private var loadingFile = false
        @State private var loadingImport = false
        @State private var importing = false
        @State private var showImportFailAlert = false
        @State private var showSeriesConfigurePage = false
        @State private var showImagePicker = false

        @Environment(\.dismiss) private var dismiss

        init(fileInfo: ImportFileInfo? = nil, fullyPresented: Binding<Bool>) {
            self._fileInfo = State(initialValue: fileInfo)
            self._fullyPresented = fullyPresented
        }
    }
}

// MARK: Views
extension LocalFileImportView.ContentView {
    var body: some View {
        PlatformNavigationStack {
            ZStack {
                if !fullyPresented {
                    halfSheetView
                } else if let fileInfo {
                    fileInfoView(fileInfo)
                }
                NavigationLink("", destination: newSeriesConfigPage, isActive: $showSeriesConfigurePage)
            }
            .padding(.horizontal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if fullyPresented {
                        Button {
                            if selectedMangaId.isEmpty {
                                showSeriesConfigurePage = true
                            } else {
                                Task {
                                    await importFile()
                                }
                            }
                        } label: {
                            if selectedMangaId.isEmpty {
                                Text(NSLocalizedString("CONTINUE"))
                            } else {
                                Text(NSLocalizedString("IMPORT")).bold()
                            }
                        }
                        .disabled(!volumeChapterValid || volumeChapterEmpty)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert(NSLocalizedString("IMPORT_FAIL"), isPresented: $showImportFailAlert) {
                Button(NSLocalizedString("OK"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("FILE_IMPORT_FAIL_TEXT"))
            }
            .sheet(isPresented: $importing) {
                DocumentPickerView(
                    allowedContentTypes: [.init(filenameExtension: "cbz")!, .zip],
                    onDocumentsPicked: { urls in
                        guard let url = urls.first else {
                            loadingImport = false
                            return
                        }
                        loadingFile = true
                        Task {
                            let importFileInfo = await LocalFileManager.shared.loadImportFileInfo(url: url)
                            if let importFileInfo {
                                fileInfo = importFileInfo
                                fullyPresented = true
                            } else {
                                showImportFailAlert = true
                            }
                            loadingFile = false
                            loadingImport = false
                        }
                    }
                )
                .ignoresSafeArea()
            }
            .onChange(of: fileInfo) { _ in
                loadFileInfoFields()
            }
            .onChange(of: importing) { newValue in
                if !newValue && !loadingFile {
                    withAnimation {
                        loadingImport = false
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                loadFileInfoFields()
            }
        }
    }

    var halfSheetView: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text(NSLocalizedString("LOCAL_FILE_IMPORT"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(NSLocalizedString("LOCAL_FILE_IMPORT_TEXT"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, -32)

            Button {
                Task {
                    await animate(duration: 0.2) {
                        loadingImport = true
                    }
                    importing = true
                }
            } label: {
                HStack {
                    if loadingImport {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "folder.fill.badge.plus")
                        Text(NSLocalizedString("IMPORT_FILE"))
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    func fileInfoView(_ fileInfo: ImportFileInfo) -> some View {
        let interItemSpacing: CGFloat = 18
        return ScrollView {
            // header
            VStack(spacing: 6) {
                ZStack {
                    if let image3 = fileInfo.previewImages[safe: 2] {
                        previewImageView(image3, scale: 0.7, offset: 22, overlayOpacity: 0.4)
                    }
                    if let image2 = fileInfo.previewImages[safe: 1] {
                        previewImageView(image2, scale: 0.9, offset: 10, overlayOpacity: 0.2)
                    }
                    if let image = fileInfo.previewImages.first {
                        previewImageView(image)
                    } else {
                        previewImageView(.mangaPlaceholder)
                    }
                }
                .padding(.bottom, 8)

                Text(fileInfo.name)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
                Text({
                    let pagesText = if fileInfo.pageCount == 1 {
                        NSLocalizedString("1_PAGE")
                    } else {
                        String(format: NSLocalizedString("%i_PAGES"), fileInfo.pageCount)
                    }
                    return [pagesText, fileInfo.fileType.localizedName]
                        .joined(separator: " • ")
                }())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.vertical, interItemSpacing)

            // fields
            VStack(spacing: interItemSpacing) {
                // name
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("CHAPTER_TITLE")).fontWeight(.medium)

                    TextFieldWrapper {
                        TextField(NSLocalizedString("CHAPTER_TITLE"), text: $name)
                            .autocorrectionDisabled()
                        if !name.isEmpty {
                            ClearFieldButton {
                                name = ""
                            }
                        }
                    }
                }

                // volume/chapter
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: interItemSpacing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString("VOLUME")).fontWeight(.medium)

                            TextFieldWrapper(hasError: !volumeChapterValid || volumeChapterEmpty) {
                                TextField(NSLocalizedString("VOLUME"), value: $volume, format: .number)
                                    .keyboardType(.decimalPad)
                                if volume != nil {
                                    ClearFieldButton {
                                        volume = nil
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(NSLocalizedString("CHAPTER")).fontWeight(.medium)

                            TextFieldWrapper(hasError: !volumeChapterValid || volumeChapterEmpty) {
                                TextField(NSLocalizedString("CHAPTER"), value: $chapter, format: .number)
                                    .keyboardType(.decimalPad)
                                if chapter != nil {
                                    ClearFieldButton {
                                        chapter = nil
                                    }
                                }
                            }
                        }
                    }

                    if !volumeChapterValid {
                        fieldTextView(NSLocalizedString("VOLUME_CHAPTER_INVALID_ERROR"), error: true)
                    } else if volumeChapterEmpty {
                        fieldTextView(NSLocalizedString("VOLUME_CHAPTER_EMPTY_ERROR"), error: true)
                    }
                }
                .onChange(of: volume) { _ in
                    validateVolumeChapter()
                }
                .onChange(of: chapter) { _ in
                    validateVolumeChapter()
                }

                // series select
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("SERIES")).fontWeight(.medium)

                    NavigationLink {
                        ListView(
                            selectedMangaId: $selectedMangaId,
                            selectedMangaTitle: $selectedMangaTitle
                        )
                    } label: {
                        TextFieldWrapper {
                            Text(selectedMangaTitle.isEmpty ? NSLocalizedString("NEW_SERIES") : selectedMangaTitle)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)

                    if selectedMangaId.isEmpty {
                        fieldTextView(NSLocalizedString("CREATE_NEW_SERIES_INFO"))
                    } else {
                        fieldTextView(NSLocalizedString("ADD_TO_OTHER_SERIES_INFO"))
                    }
                }
                .onChange(of: selectedMangaId) { _ in
                    validateSeriesName()
                    Task {
                        if !selectedMangaId.isEmpty {
                            volume = nil
                            chapter = await LocalFileDataManager.shared.getNextChapterNumber(series: selectedMangaId)
                            validateVolumeChapter()
                        } else {
                            volume = nil
                            chapter = 1
                            volumeChapterValid = true
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboardInteractively()
    }

    func previewImageView(
        _ image: PlatformImage,
        imageHeight: CGFloat = 130,
        scale: CGFloat = 1,
        offset: CGFloat = 0,
        overlayOpacity: CGFloat = 0
    ) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: imageHeight * 2/3, height: imageHeight)
            .overlay { Color.black.opacity(overlayOpacity) }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(UIColor.quaternarySystemFill), lineWidth: 1)
            )
            .scaleEffect(scale)
            .offset(x: offset)
    }

    func fieldTextView(_ text: String, error: Bool = false) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(error ? .red : Color.secondary)
            .padding(.top, 2)
            .padding(.horizontal, 6)
    }
}

// MARK: Functions
extension LocalFileImportView.ContentView {
    func loadFileInfoFields() {
        guard let fileInfo else { return }
        name = fileInfo.name.removingExtension()
        seriesName = name
        coverImage = fileInfo.previewImages.first
        Task {
            nameValid = !(await LocalFileDataManager.shared.hasSeries(name: seriesName))
        }
    }

    // ensure there's at least a volume or a chapter number
    // and there are no other chapters with those numbers (if a series is selected)
    func validateVolumeChapter() {
        volumeChapterEmpty = volume == nil && chapter == nil
        if selectedMangaId.isEmpty {
            volumeChapterValid = true
        } else {
            Task {
                volumeChapterValid = !(await LocalFileDataManager.shared.hasChapter(
                    series: selectedMangaId,
                    volume: volume,
                    chapter: chapter
                ))
            }
        }
    }

    // ensure no series has the currently entered name (if we're making a new series)
    // and the name isn't empty (if we're making a new series)
    func validateSeriesName() {
        if selectedMangaId.isEmpty {
            nameEmpty = seriesName.isEmpty
            Task {
                nameValid = !(await LocalFileDataManager.shared.hasSeries(name: seriesName))
            }
        } else {
            nameEmpty = false
            nameValid = true
        }
    }

    func importFile() async {
        guard let fileInfo else { return }
        do {
            try await LocalFileManager.shared.uploadFile(
                from: fileInfo.url,
                mangaId: selectedMangaId.isEmpty ? nil : selectedMangaId,
                mangaCoverImage: selectedMangaId.isEmpty ? coverImage : nil,
                mangaName: selectedMangaId.isEmpty ? seriesName : nil,
                mangaDescription: selectedMangaId.isEmpty ? seriesDescription : nil,
                chapterName: name,
                volume: volume,
                chapter: chapter
            )
            NotificationCenter.default.post(name: .init("refresh-content"), object: nil)
            dismiss()
        } catch {
            LogManager.logger.error("Unable import file: \(error)")
            showImportFailAlert = true
        }
    }
}

// MARK: New Series Config Page
extension LocalFileImportView.ContentView {
    var newSeriesConfigPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                Button {
                    showImagePicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        previewImageView(
                            coverImage ?? .mangaPlaceholder,
                            imageHeight: 150
                        )
                        Image(systemName: "pencil.circle.fill")
                            .imageScale(.large)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .offset(x: 10, y: 10)
                    }
                }
                .padding(.top, 12)

                // title
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("SERIES_TITLE")).fontWeight(.medium)

                    TextFieldWrapper(hasError: !nameValid || nameEmpty) {
                        TextField(NSLocalizedString(NSLocalizedString("SERIES_TITLE")), text: $seriesName)
                            .autocorrectionDisabled()
                        if !seriesName.isEmpty {
                            ClearFieldButton {
                                seriesName = ""
                            }
                        }
                    }

                    if !nameValid {
                        fieldTextView(NSLocalizedString("SERIES_TITLE_UNIQUE_ERROR"), error: true)
                    } else if nameEmpty {
                        fieldTextView(NSLocalizedString("SERIES_TITLE_EMPTY_ERROR"), error: true)
                    }
                }
                .onChange(of: seriesName) { _ in
                    validateSeriesName()
                }

                // description
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("DESCRIPTION"))
                        .fontWeight(.medium)

                    TextFieldWrapper {
                        if #available(iOS 16.0, *) {
                            TextField(NSLocalizedString("DESCRIPTION"), text: $seriesDescription, axis: .vertical)
                                .autocorrectionDisabled()
                                .lineLimit(4)
                                .foregroundStyle(Color.clear)
                                .overlay {
                                    TextEditor(text: $seriesDescription)
                                        .scrollClipDisabledPlease()
                                        .scrollContentBackground(.hidden)
                                        .padding(.horizontal, -5)
                                        .padding(.vertical, -8)
                                }
                        } else {
                            TextField(NSLocalizedString("DESCRIPTION"), text: $seriesDescription)
                                .autocorrectionDisabled()
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $coverImage)
                .ignoresSafeArea()
        }
        .scrollDismissesKeyboardInteractively()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await importFile()
                    }
                } label: {
                    Text(NSLocalizedString("IMPORT")).bold()
                }
                .disabled(!nameValid || !volumeChapterValid || nameEmpty || volumeChapterEmpty)
            }
        }
        .navigationTitle(NSLocalizedString("NEW_SERIES"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Series List View
extension LocalFileImportView.ContentView {
    struct ListView: View {
        @Binding var selectedMangaId: String
        @Binding var selectedMangaTitle: String

        @State private var searchText = ""
        @State private var series: [LocalSeriesInfo] = []
        @State private var searchTask: Task<(), Never>?

        var body: some View {
            ScrollView {
                LazyVStack {
                    if searchText.isEmpty {
                        seriesView(
                            id: "",
                            imageUrl: nil,
                            title: NSLocalizedString("NEW_SERIES"),
                            subtitle: NSLocalizedString("NEW_SERIES_TEXT")
                        )
                    }

                    ForEach(series, id: \.self) { item in
                        seriesView(
                            id: item.name,
                            imageUrl: item.coverUrl,
                            title: item.name,
                            subtitle: {
                                if item.chapterCount == 1 {
                                    NSLocalizedString("1_CHAPTER")
                                } else {
                                    String(format: NSLocalizedString("%i_CHAPTERS"), item.chapterCount)
                                }
                            }().lowercased()
                        )
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(NSLocalizedString("SELECT_SERIES"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { _ in
                searchTask?.cancel()
                searchTask = Task {
                    let results = await LocalFileDataManager.shared.fetchLocalSeriesInfo(query: searchText)
                    withAnimation {
                        series = results
                    }
                }
            }
            .task {
                let results = await LocalFileDataManager.shared.fetchLocalSeriesInfo()
                withAnimation {
                    series = results
                }
            }
        }

        func seriesView(
            id: String,
            imageUrl: String? = nil,
            title: String,
            subtitle: String
        ) -> some View {
            Button {
                selectedMangaId = id
                selectedMangaTitle = title
            } label: {
                HStack(spacing: 14) {
                    if let imageUrl {
                        MangaCoverView(
                            coverImage: imageUrl,
                            width: 80 * 2/3,
                            height: 80
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .aspectRatio(2/3, contentMode: .fit)
                            .frame(height: 80)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: UIFont.labelFontSize, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text(title)
                            .lineLimit(1)
                        Text(subtitle)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if selectedMangaId == id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .padding()
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .buttonStyle(HighlightButtonStyle())
            .foregroundStyle(.primary)
            .padding(.horizontal)
        }
    }

    private struct HighlightButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background {
                    if configuration.isPressed {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(uiColor: .systemGray4))
                    }
                }
        }
    }
}

// MARK: PresentationDetentHandler
// handles the sheet changing from a half sheet to a full screen
// only supported on ios 16+
@available(iOS 16.0, *)
private struct PresentationDetentHandler<Content: View & Sendable>: View {
    @Binding var fullyPresented: Bool
    @ViewBuilder let content: Content

    @State private var detents: Set<PresentationDetent> = [.height(220)]
    @State private var detent: PresentationDetent = .height(220)

    private let defaultDetent = PresentationDetent.height(220)

    var body: some View {
        content
            .presentationDetents(detents, selection: $detent)
            .presentationDragIndicator(.hidden)
            .onChange(of: fullyPresented) { newValue in
                if newValue {
                    Task {
                        detents = [defaultDetent, .large]
                        await AnyView.animate(duration: 0.2) {
                            detent = .large
                        }
                        detents = [.large]
                    }
                }
            }
    }
}

@available(iOS 17.0, *)
#Preview {
    @Previewable @State var presenting = false

    Button("Present") {
        presenting = true
    }
    .sheet(isPresented: $presenting) {
        LocalFileImportView()
    }
}

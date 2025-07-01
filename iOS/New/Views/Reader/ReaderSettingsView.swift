//
//  ReaderSettingsView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/30/25.
//

import SwiftUI

struct ReaderSettingsView: View {
    let mangaId: String

    @State private var readingMode: ReadingMode?
    @StateObject private var downsampleImages = UserDefaultsBool(key: "Reader.downsampleImages")
    @StateObject private var upscaleImages = UserDefaultsBool(key: "Reader.upscaleImages")

    @Environment(\.dismiss) private var dismiss

    init(mangaId: String) {
        self.mangaId = mangaId
        self._readingMode = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.readingMode.\(mangaId)")
                .flatMap(ReadingMode.init)
        )
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                Section(NSLocalizedString("GENERAL")) {
                    SettingView(
                        setting: .init(
                            key: "Reader.readingMode.\(mangaId)",
                            title: NSLocalizedString("READING_MODE"),
                            notification: Notification.Name.readerReadingMode.rawValue,
                            value: .select(.init(
                                values: ["default", "auto", "rtl", "ltr", "vertical", "webtoon"],
                                titles: [
                                    NSLocalizedString("DEFAULT"),
                                    NSLocalizedString("AUTOMATIC"),
                                    NSLocalizedString("RTL"),
                                    NSLocalizedString("LTR"),
                                    NSLocalizedString("VERTICAL"),
                                    NSLocalizedString("WEBTOON")
                                ]
                            ))
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.skipDuplicateChapters",
                            title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.downsampleImages",
                            title: NSLocalizedString("DOWNSAMPLE_IMAGES"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.skipDuplicateChapters",
                            title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.cropBorders",
                            title: NSLocalizedString("CROP_BORDERS"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.saveImageOption",
                            title: NSLocalizedString("SAVE_IMAGE_OPTION"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.backgroundColor",
                            title: NSLocalizedString("READER_BG_COLOR"),
                            value: .select(.init(
                                values: ["system", "white", "black"],
                                titles: [
                                    NSLocalizedString("READER_BG_COLOR_SYSTEM"),
                                    NSLocalizedString("READER_BG_COLOR_WHITE"),
                                    NSLocalizedString("READER_BG_COLOR_BLACK")
                                ]
                            ))
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.orientation",
                            title: NSLocalizedString("READER_ORIENTATION"),
                            notification: "Reader.orientation",
                            value: .select(.init(
                                values: ["device", "portrait", "landscape"],
                                titles: [
                                    NSLocalizedString("FOLLOW_DEVICE"),
                                    NSLocalizedString("PORTRAIT"),
                                    NSLocalizedString("LANDSCAPE")
                                ]
                            ))
                        )
                    )
                }

                if #available(iOS 16.0, *), !downsampleImages.value {
                    Section {
                        SettingView(
                            setting: .init(
                                key: "Reader.upscaleImages",
                                title: NSLocalizedString("UPSCALE_IMAGES"),
                                value: .toggle(.init())
                            )
                        )
                        if upscaleImages.value {
                            NavigationLink(destination: UpscaleModelListView()) {
                                Text(NSLocalizedString("UPSCALING_MODELS"))
                            }
                            SettingView(
                                setting: .init(
                                    key: "Reader.upscaleMaxHeight",
                                    title: NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT"),
                                    value: .stepper(.init(
                                        minimumValue: 200,
                                        maximumValue: 4000,
                                        stepValue: 100
                                    ))
                                )
                            )
                        }
                    } header: {
                        Text(NSLocalizedString("UPSCALING"))
                    } footer: {
                        Text(NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT_TEXT"))
                    }
                }

                if readingMode == .rtl || readingMode == .ltr || readingMode == .vertical || readingMode == nil {
                    Section(NSLocalizedString("PAGED")) {
                        SettingView(
                            setting: .init(
                                key: "Reader.pagesToPreload",
                                title: NSLocalizedString("PAGES_TO_PRELOAD"),
                                value: .stepper(.init(minimumValue: 1, maximumValue: 10))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.pagedPageLayout",
                                title: NSLocalizedString("PAGE_LAYOUT"),
                                value: .select(.init(
                                    values: ["single", "double", "auto"],
                                    titles: [
                                        NSLocalizedString("SINGLE_PAGE"),
                                        NSLocalizedString("DOUBLE_PAGE"),
                                        NSLocalizedString("AUTOMATIC")
                                    ]
                                ))
                            )
                        )
                    }
                }

                if readingMode == .webtoon || readingMode == .continuous || readingMode == nil {
                    Section {
                        SettingView(
                            setting: .init(
                                key: "Reader.verticalInfiniteScroll",
                                title: NSLocalizedString("INFINITE_VERTICAL_SCROLL"),
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.pillarbox",
                                title: NSLocalizedString("PILLARBOX"),
                                value: .toggle(.init())
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.pillarboxAmount",
                                title: NSLocalizedString("PILLARBOX_AMOUNT"),
                                requires: "Reader.pillarbox",
                                value: .stepper(.init(minimumValue: 0, maximumValue: 100, stepValue: 5))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.pillarboxOrientation",
                                title: NSLocalizedString("PILLARBOX_ORIENTATION"),
                                requires: "Reader.pillarbox",
                                value: .select(.init(
                                    values: ["both", "portrait", "landscape"],
                                    titles: [
                                        NSLocalizedString("BOTH"),
                                        NSLocalizedString("PORTRAIT"),
                                        NSLocalizedString("LANDSCAPE")
                                    ]
                                ))
                            )
                        )
                    } header: {
                        Text(NSLocalizedString("WEBTOON"))
                    } footer: {
                        Text(NSLocalizedString("PILLARBOX_ORIENTATION_INFO"))
                    }
                }
            }
            .animation(.default, value: downsampleImages.value)
            .animation(.default, value: upscaleImages.value)
            .navigationTitle(NSLocalizedString("READER_SETTINGS"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("DONE")).bold()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerReadingMode)) { _ in
                readingMode = UserDefaults.standard.string(forKey: "Reader.readingMode.\(mangaId)").flatMap(ReadingMode.init)
            }
        }
    }
}

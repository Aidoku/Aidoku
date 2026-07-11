//
//  ReaderSettingsView.swift
//  Aidoku (iOS)
//
//  Created by Skitty on 6/30/25.
//

import SwiftUI

struct ReaderSettingsView: View {
    let mangaId: MangaIdentifier
    let reader: ReaderViewController.Reader

    @State private var readingMode: ReadingMode?
    @State private var tapZones: DefaultTapZones
    @State private var dictionaryLookupGestureMode: String
    @State private var dictionaryLookupEnabled: Bool
    @State private var dictionaryTextOverlayModeEnabled: Bool
    @StateObject private var downsampleImages = UserDefaultsBool(key: "Reader.downsampleImages")
    @StateObject private var upscaleImages = UserDefaultsBool(key: "Reader.upscaleImages")
    @StateObject private var splitWideImages = UserDefaultsBool(key: "Reader.splitWideImages")

    // All available font families on the system
    private static let availableFonts: [String] = {
        var fonts = UIFont.familyNames.sorted()
        // Add "System" at the beginning for the default SF font
        fonts.insert("System", at: 0)
        return fonts
    }()

    @Environment(\.dismiss) private var dismiss

    init(mangaId: MangaIdentifier, reader: ReaderViewController.Reader) {
        self.mangaId = mangaId
        self.reader = reader
        self._readingMode = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.readingMode.\(mangaId)")
                .flatMap(ReadingMode.init)
        )
        self._tapZones = State(
            initialValue: UserDefaults.standard.string(forKey: "Reader.tapZones")
                .flatMap(DefaultTapZones.init) ?? .disabled
        )
        self._dictionaryLookupGestureMode = State(
            initialValue: UserDefaults.standard.string(forKey: "Dictionary.lookupGesture") ?? "single-tap"
        )
        self._dictionaryLookupEnabled = State(
            initialValue: UserDefaults.standard.bool(forKey: "Dictionary.enable")
        )
        self._dictionaryTextOverlayModeEnabled = State(
            initialValue: UserDefaults.standard.bool(forKey: "Dictionary.textOverlayMode")
        )
    }

    var body: some View {
        PlatformNavigationStack {
            List {
                Section(NSLocalizedString("GENERAL")) {
                    let readingModeKey = "Reader.readingMode.\(mangaId)"
                    SettingView(
                        setting: .init(
                            key: readingModeKey,
                            title: NSLocalizedString("READING_MODE"),
                            notification: .init(readingModeKey),
                            value: .select(.init(
                                values: [
                                    "default",
                                    "auto",
                                    "rtl",
                                    "ltr",
                                    "vertical",
                                    "webtoon",
                                    "continuous"
                                ],
                                titles: [
                                    NSLocalizedString("DEFAULT"),
                                    NSLocalizedString("AUTOMATIC"),
                                    NSLocalizedString("RTL"),
                                    NSLocalizedString("LTR"),
                                    NSLocalizedString("VERTICAL"),
                                    NSLocalizedString("WEBTOON"),
                                    NSLocalizedString("CONTINUOUS_WITH_GAPS")
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
                            key: "Reader.markDuplicateChapters",
                            title: NSLocalizedString("MARK_DUPLICATE_CHAPTERS"),
                            value: .toggle(.init())
                        )
                    )
                    if reader != .text {
                        SettingView(
                            setting: .init(
                                key: "Reader.downsampleImages",
                                title: NSLocalizedString("DOWNSAMPLE_IMAGES"),
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
                                key: "Reader.disableDoubleTap",
                                title: NSLocalizedString("DISABLE_DOUBLE_TAP_ZOOM"),
                                value: .toggle(.init())
                            )
                        )
                    }
                    SettingView(
                        setting: .init(
                            key: "Reader.disableQuickActions",
                            title: NSLocalizedString("DISABLE_QUICK_ACTIONS"),
                            requiresFalse: "Dictionary.lookupGestureLocksQuickActions",
                            value: .toggle(.init(subtitle: NSLocalizedString("LOOKUP_GESTURE_LOCKS_QUICK_ACTIONS")))
                        ),
                        onChange: onSettingChange
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.liveText",
                            title: NSLocalizedString("LIVE_TEXT"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.hideBarsOnSwipe",
                            title: NSLocalizedString("HIDE_BARS_ON_SWIPE"),
                            value: .toggle(.init())
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Reader.backgroundColor",
                            title: NSLocalizedString("READER_BG_COLOR"),
                            value: .select(.init(
                                values: ["system", "auto", "white", "black"],
                                titles: [
                                    NSLocalizedString("READER_BG_COLOR_SYSTEM"),
                                    NSLocalizedString("READER_BG_COLOR_AUTO"),
                                    NSLocalizedString("READER_BG_COLOR_WHITE"),
                                    NSLocalizedString("READER_BG_COLOR_BLACK")
                                ]
                            ))
                        )
                    )
                    if UIDevice.current.userInterfaceIdiom != .pad {
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
                }

                if #available(iOS 18.0, *) {
                    dictionarySection
                }

                Section {
                    NavigationLink(destination: TapZonesSelectView()) {
                        HStack {
                            Text(NSLocalizedString("TAP_ZONES"))
                            Spacer()
                            Text(tapZones.title)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingView(
                        setting: .init(
                            key: "Reader.invertTapZones",
                            title: NSLocalizedString("INVERT_TAP_ZONES"),
                            value: .toggle(.init())
                        )
                    )

                    SettingView(
                        setting: .init(
                            key: "Reader.animatePageTransitions",
                            title: NSLocalizedString("ANIMATE_PAGE_TRANSITIONS"),
                            value: .toggle(.init())
                        )
                    )
                } header: {
                    Text(NSLocalizedString("TAP_ZONES"))
                }

                if reader == .text {
                    // Text Reader Settings
                    Section(String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("TEXT_READER"))) {
                        SettingView(
                            setting: .init(
                                key: "Reader.textReaderStyle",
                                title: NSLocalizedString("TEXT_READER_STYLE"),
                                notification: .init("Reader.textReaderStyle"),
                                value: .select(.init(
                                    values: ["paged", "scroll"],
                                    titles: [
                                        NSLocalizedString("TEXT_READER_PAGED"),
                                        NSLocalizedString("TEXT_READER_SCROLL")
                                    ]
                                ))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textFontFamily",
                                title: NSLocalizedString("TEXT_FONT_FAMILY"),
                                notification: .init("Reader.textFontFamily"),
                                value: .select(.init(
                                    values: Self.availableFonts
                                ))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textFontSize",
                                title: NSLocalizedString("TEXT_FONT_SIZE"),
                                notification: .init("Reader.textFontSize"),
                                value: .stepper(.init(minimumValue: 12, maximumValue: 32, stepValue: 2))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textLineSpacing",
                                title: NSLocalizedString("TEXT_LINE_SPACING"),
                                notification: .init("Reader.textLineSpacing"),
                                value: .stepper(.init(minimumValue: 0, maximumValue: 24, stepValue: 2))
                            )
                        )
                        SettingView(
                            setting: .init(
                                key: "Reader.textHorizontalPadding",
                                title: NSLocalizedString("TEXT_HORIZONTAL_PADDING"),
                                notification: .init("Reader.textHorizontalPadding"),
                                value: .stepper(.init(minimumValue: 8, maximumValue: 48, stepValue: 4))
                            )
                        )
                    }
                } else {
                    if !downsampleImages.value {
                        Section {
                            SettingView(
                                setting: .init(
                                    key: "Reader.upscaleImages",
                                    title: String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("UPSCALE_IMAGES")),
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
                            if upscaleImages.value {
                                Text(NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT_TEXT"))
                            }
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
                            let pageOffsetKey = "Reader.pagedPageOffset.\(mangaId)"
                            SettingView(
                                setting: .init(
                                    key: pageOffsetKey,
                                    title: NSLocalizedString("PAGE_OFFSET"),
                                    notification: .init(pageOffsetKey),
                                    value: .toggle(.init())
                                )
                            )
                            SettingView(
                                setting: .init(
                                    key: "Reader.splitWideImages",
                                    title: NSLocalizedString("SPLIT_WIDE_IMAGES"),
                                    notification: .init("Reader.splitWideImages"),
                                    value: .toggle(.init())
                                )
                            )
                            if splitWideImages.value {
                                SettingView(
                                    setting: .init(
                                        key: "Reader.reverseSplitOrder",
                                        title: NSLocalizedString("REVERSE_SPLIT_ORDER"),
                                        notification: .init("Reader.reverseSplitOrder"),
                                        value: .toggle(.init())
                                    )
                                )
                            }
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
                                    value: .stepper(.init(minimumValue: 5, maximumValue: 95, stepValue: 5))
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
            }
            .animation(.default, value: downsampleImages.value)
            .animation(.default, value: upscaleImages.value)
            .animation(.default, value: splitWideImages.value)
            .navigationTitle(NSLocalizedString("READER_SETTINGS"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton {
                        dismiss()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerReadingMode)) { _ in
                readingMode = UserDefaults.standard.string(forKey: "Reader.readingMode.\(mangaId)").flatMap(ReadingMode.init)
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerTapZones)) { _ in
                tapZones = UserDefaults.standard.string(forKey: "Reader.tapZones").flatMap(DefaultTapZones.init) ?? .disabled
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("Dictionary.enable"))) { _ in
                dictionaryLookupEnabled = UserDefaults.standard.bool(forKey: "Dictionary.enable")
                onSettingChange("Dictionary.enable")
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("Dictionary.lookupGesture"))) { _ in
                dictionaryLookupGestureMode = UserDefaults.standard.string(forKey: "Dictionary.lookupGesture") ?? "single-tap"
                onSettingChange("Dictionary.lookupGesture")
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("Dictionary.textOverlayMode"))) { _ in
                dictionaryTextOverlayModeEnabled = UserDefaults.standard.bool(forKey: "Dictionary.textOverlayMode")
            }
        }
    }

    private func onSettingChange(_ key: String) {
        guard key == "Dictionary.enable" || key == "Dictionary.lookupGesture" else { return }
        UserDefaults.standard.syncReaderLookupGestureCompatibilityLocks()
    }
}

extension ReaderSettingsView {
    @available(iOS 18.0, *)
    var dictionarySection: some View {
        Section {
            SettingView(
                setting: .init(
                    key: "Dictionary.enable",
                    title: NSLocalizedString("DICTIONARY_LOOKUP"),
                    value: .toggle(.init())
                )
            )
            if dictionaryLookupEnabled {
                NavigationLink(destination: DictionaryListView()) {
                    Text(NSLocalizedString("DICTIONARIES"))
                }
                SettingView(
                    setting: .init(
                        key: "Dictionary.lookupGesture",
                        title: NSLocalizedString("LOOKUP_GESTURE"),
                        value: .select(.init(
                            values: ["single-tap", "long-press"],
                            titles: [
                                NSLocalizedString("SINGLE_TAP"),
                                NSLocalizedString("LONG_PRESS")
                            ]
                        ))
                    ),
                    onChange: onSettingChange
                )
                SettingView(
                    setting: .init(
                        key: "Dictionary.textOverlayMode",
                        title: NSLocalizedString("DICTIONARY_TEXT_OVERLAY_MODE"),
                        value: .toggle(.init(subtitle: NSLocalizedString("DICTIONARY_TEXT_OVERLAY_MODE_INFO")))
                    )
                )
                if dictionaryTextOverlayModeEnabled {
                    SettingView(
                        setting: .init(
                            key: "Dictionary.overlayPadding",
                            title: NSLocalizedString("DICTIONARY_OVERLAY_PADDING"),
                            value: .stepper(.init(
                                minimumValue: 0,
                                maximumValue: 10,
                                stepValue: 1
                            ))
                        )
                    )
                    SettingView(
                        setting: .init(
                            key: "Dictionary.overlayTextScaleMultiplier",
                            title: NSLocalizedString("DICTIONARY_OVERLAY_TEXT_SCALE"),
                            value: .stepper(.init(
                                minimumValue: 0.5,
                                maximumValue: 1.25,
                                stepValue: 0.05
                            ))
                        )
                    )
                }
                SettingView(
                    setting: .init(
                        key: "Dictionary.OCRPreUpscale",
                        title: NSLocalizedString("DICTIONARY_OCR_PRE_UPSCALE"),
                        requiresFalse: "Reader.upscaleImages",
                        value: .toggle(.init(
                            subtitle: NSLocalizedString("DICTIONARY_OCR_PRE_UPSCALE_DISABLED_INFO")
                        ))
                    )
                )
                SettingView(
                    setting: .init(
                        key: "Dictionary.popupWidth",
                        title: NSLocalizedString("DICTIONARY_POPUP_WIDTH"),
                        value: .stepper(.init(
                            minimumValue: 220,
                            maximumValue: 500,
                            stepValue: 10
                        ))
                    )
                )
                SettingView(
                    setting: .init(
                        key: "Dictionary.popupHeight",
                        title: NSLocalizedString("DICTIONARY_POPUP_HEIGHT"),
                        value: .stepper(.init(
                            minimumValue: 160,
                            maximumValue: 350,
                            stepValue: 10
                        ))
                    )
                )
            }
        } header: {
            Text(NSLocalizedString("DICTIONARY_LOOKUP"))
        } footer: {
            if dictionaryLookupEnabled && dictionaryLookupGestureMode == "single-tap" {
                Text(NSLocalizedString("LOOKUP_GESTURE_SINGLE_TAP_HINT"))
            }
        }
    }
}

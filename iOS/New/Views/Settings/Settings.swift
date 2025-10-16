//
//  Settings.swift
//  Aidoku
//
//  Created by Skitty on 9/20/25.
//

import AidokuRunner
import Foundation

enum Settings {
    static let settings: [Setting] = [
        .init(value: .group(.init(items: [
            .init(
                key: "General.incognitoMode",
                title: NSLocalizedString("INCOGNITO_MODE"),
                value: .toggle(.init(subtitle: NSLocalizedString("INCOGNITO_MODE_TEXT")))
            )
        ]))),
        .init(value: .group(.init(items: [
            .init(
                title: NSLocalizedString("APPEARANCE"),
                value: .page(.init(
                    items: appearanceSettings,
                    inlineTitle: true,
                    icon: .system(name: "textformat.size", color: "blue")
                ))
            ),
            .init(
                title: NSLocalizedString("LIBRARY"),
                value: .page(.init(
                    items: librarySettings,
                    inlineTitle: true,
                    icon: .system(name: "books.vertical.fill", color: "red")
                ))
            ),
            .init(
                title: NSLocalizedString("READER"),
                value: .page(.init(
                    items: readerSettings,
                    inlineTitle: true,
                    icon: .system(name: "book.fill", color: "green")
                ))
            ),
            .init(
                key: "Tracking",
                title: NSLocalizedString("TRACKING"),
                value: .page(.init(
                    items: [],
                    inlineTitle: true,
                    icon: .system(name: "clock.arrow.2.circlepath", color: "orange", inset: 4)
                ))
            ),
            .init(
                title: NSLocalizedString("ICLOUD_SYNC"),
                value: .page(.init(
                    items: [
                        .init(value: .group(.init(items: [
                            .init(
                                key: "General.icloudSync",
                                title: String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("ICLOUD_SYNC")),
                                requires: "isiCloudAvailable",
                                value: .toggle(.init())
                            )
                        ])))
                    ],
                    icon: .system(name: "icloud.fill", color: "blue"),
                    info: NSLocalizedString(
                        UserDefaults.standard.bool(forKey: "isSideloaded")
                            ? "ICLOUD_SYNC_TEXT_SIDELOADED"
                            : "ICLOUD_SYNC_TEXT_EXPERIMENTAL"
                    )
                ))
            ),
            .init(
                title: NSLocalizedString("ADVANCED"),
                value: .page(.init(
                    items: advancedSettings,
                    inlineTitle: true,
                    icon: .system(name: "gearshape.2.fill", color: "gray", inset: 4)
                ))
            )
        ]))),
        .init(value: .group(.init(items: [
            .init(
                key: "About",
                title: NSLocalizedString("ABOUT"),
                value: .page(.init(
                    items: [],
                    inlineTitle: true,
                    icon: .system(name: "info.circle.fill", color: "gray", inset: 6)
                ))
            ),
            .init(
                key: "SourceLists",
                title: NSLocalizedString("SOURCE_LISTS"),
                value: .page(.init(
                    items: [],
                    inlineTitle: true,
                    icon: .system(name: "globe", color: "green")
                ))
            ),
            .init(
                key: "Backups",
                title: NSLocalizedString("BACKUPS"),
                value: .page(.init(
                    items: [],
                    inlineTitle: true,
                    icon: .system(name: "externaldrive.fill", color: "red")
                ))
            ),
            .init(
                key: "DownloadManager",
                title: NSLocalizedString("DOWNLOAD_MANAGER"),
                value: .page(.init(
                    items: [],
                    inlineTitle: true,
                    icon: .system(name: "arrow.down.circle.fill", color: "blue", inset: 6)
                ))
            )
        ])))
    ]
}

extension Settings {
    private static let appearanceSettings: [Setting] = [
        .init(value: .group(.init(items: [
            .init(
                key: "General.appearance",
                title: NSLocalizedString("APPEARANCE"),
                requiresFalse: "General.useSystemAppearance",
                value: .segment(.init(options: [
                    NSLocalizedString("APPEARANCE_LIGHT"),
                    NSLocalizedString("APPEARANCE_DARK")
                ]))
            ),
            .init(
                key: "General.useSystemAppearance",
                title: NSLocalizedString("USE_SYSTEM_APPEARANCE"),
                value: .toggle(.init())
            )
        ]))),
        .init(
            title: NSLocalizedString("MANGA_PER_ROW"),
            value: .group(.init(items: [
                .init(
                    key: "General.portraitRows",
                    title: NSLocalizedString("PORTRAIT"),
                    value: .stepper(.init(minimumValue: 1, maximumValue: 15))
                ),
                .init(
                    key: "General.landscapeRows",
                    title: NSLocalizedString("LANDSCAPE"),
                    value: .stepper(.init(minimumValue: 1, maximumValue: 15))
                )
            ]))
        )
    ]

    private static let librarySettings: [Setting] = [
        .init(value: .group(.init(items: [
            .init(
                key: "Library.opensReaderView",
                title: NSLocalizedString("OPEN_READER_VIEW"),
                value: .toggle(.init())
            ),
            .init(
                key: "Library.unreadChapterBadges",
                title: NSLocalizedString("UNREAD_CHAPTER_BADGES"),
                value: .toggle(.init())
            ),
            .init(
                key: "Library.pinManga",
                title: NSLocalizedString("PIN_MANGA"),
                value: .toggle(.init())
            ),
            .init(
                key: "Library.pinMangaType",
                title: NSLocalizedString("PIN_MANGA_TYPE"),
                requires: "Library.pinManga",
                value: .segment(.init(options: [
                    NSLocalizedString("PIN_MANGA_UNREAD"),
                    NSLocalizedString("PIN_MANGA_UPDATED")
                ]))
            )
        ]))),
        .init(value: .group(.init(items: [
            .init(
                key: "Library.lockLibrary",
                title: NSLocalizedString("LOCK_LIBRARY"),
                notification: "updateLibraryLock",
                value: .toggle(.init(authToDisable: true))
            ),
            .init(
                key: "History.lockHistoryTab",
                title: NSLocalizedString("LOCK_HISTORY_TAB"),
                value: .toggle(.init(authToDisable: true))
            )
        ]))),
        .init(
            title: NSLocalizedString("CATEGORIES"),
            value: .group(.init(items: [
                .init(
                    key: "Library.categories",
                    title: NSLocalizedString("CATEGORIES"),
                    value: .page(.init(items: []))
                ),
                .init(
                    key: "Library.defaultCategory",
                    title: NSLocalizedString("DEFAULT_CATEGORY"),
                    value: .custom
                ),
                .init(
                    key: "Library.lockedCategories",
                    title: NSLocalizedString("LOCKED_CATEGORIES"),
                    notification: "updateLibraryLock",
                    requires: "Library.lockLibrary",
                    value: .custom
                )
            ]))
        ),
        .init(
            title: NSLocalizedString("LIBRARY_UPDATING"),
            value: .group(.init(items: [
                .init(
                    key: "Library.updateInterval",
                    title: NSLocalizedString("UPDATE_INTERVAL"),
                    value: .select(.init(
                        values: ["never", "12hours", "daily", "2days", "weekly"],
                        titles: [
                            NSLocalizedString("NEVER"),
                            NSLocalizedString("EVERY_12_HOURS"),
                            NSLocalizedString("DAILY"),
                            NSLocalizedString("EVERY_2_DAYS"),
                            NSLocalizedString("WEEKLY")
                        ]
                    ))
                ),
                .init(
                    key: "Library.skipTitles",
                    title: NSLocalizedString("SKIP_TITLES"),
                    value: .multiselect(.init(
                        values: ["hasUnread", "completed", "notStarted"],
                        titles: [
                            NSLocalizedString("WITH_UNREAD_CHAPTERS"),
                            NSLocalizedString("WITH_COMPLETED_STATUS"),
                            NSLocalizedString("THAT_HAVENT_BEEN_READ")
                        ]
                    ))
                ),
                .init(
                    key: "Library.excludedUpdateCategories",
                    title: NSLocalizedString("EXCLUDED_CATEGORIES"),
                    value: .custom
                ),
                .init(
                    key: "Library.updateOnlyOnWifi",
                    title: NSLocalizedString("ONLY_UPDATE_ON_WIFI"),
                    value: .toggle(.init())
                ),
                .init(
                    key: "Library.downloadOnlyOnWifi",
                    title: NSLocalizedString("ONLY_DOWNLOAD_ON_WIFI"),
                    value: .toggle(.init())
                ),
                .init(
                    key: "Library.refreshMetadata",
                    title: NSLocalizedString("REFRESH_METADATA"),
                    value: .toggle(.init())
                ),
                .init(
                    key: "Library.deleteDownloadAfterReading",
                    title: NSLocalizedString("DELETE_DOWNLOAD_AFTER_READING"),
                    value: .toggle(.init())
                )
            ]))
        )
    ]

    private static let readerSettings: [Setting] = [
        .init(value: .group(.init(items: [
            .init(
                key: "Reader.readingMode",
                title: NSLocalizedString("READING_MODE"),
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
            ),
            .init(
                key: "Reader.skipDuplicateChapters",
                title: NSLocalizedString("SKIP_DUPLICATE_CHAPTERS"),
                value: .toggle(.init())
            ),
            .init(
                key: "Reader.markDuplicateChapters",
                title: NSLocalizedString("MARK_DUPLICATE_CHAPTERS"),
                value: .toggle(.init())
            ),
            .init(
                key: "Reader.downsampleImages",
                title: NSLocalizedString("DOWNSAMPLE_IMAGES"),
                value: .toggle(.init())
            ),
            .init(
                key: "Reader.cropBorders",
                title: NSLocalizedString("CROP_BORDERS"),
                value: .toggle(.init())
            ),
            .init(
                key: "Reader.disableQuickActions",
                title: NSLocalizedString("DISABLE_QUICK_ACTIONS"),
                value: .toggle(.init())
            ),
            .init(
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
            ),
            .init(
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
        ]))),
        .init(
            title: NSLocalizedString("TAP_ZONES"),
            value: .group(.init(items: [
                .init(
                    key: "Reader.tapZones",
                    title: NSLocalizedString("TAP_ZONES"),
                    value: .select(.init(
                        values: DefaultTapZones.allCases.map { $0.value },
                        titles: DefaultTapZones.allCases.map { $0.title }
                    ))
                ),
                .init(
                    key: "Reader.invertTapZones",
                    title: NSLocalizedString("INVERT_TAP_ZONES"),
                    value: .toggle(.init())
                ),
                .init(
                    key: "Reader.animatePageTransitions",
                    title: NSLocalizedString("ANIMATE_PAGE_TRANSITIONS"),
                    value: .toggle(.init())
                )
            ]))
        ),
        .init(
            title: NSLocalizedString("UPSCALING"),
            value: .group(.init(
                footer: NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT_TEXT"),
                items: [
                    .init(
                        key: "Reader.upscaleImages",
                        title: String(format: NSLocalizedString("%@_EXPERIMENTAL"), NSLocalizedString("UPSCALE_IMAGES")),
                        requiresFalse: "Reader.downsampleImages",
                        value: .toggle(.init())
                    ),
                    .init(
                        key: "Reader.upscalingModels",
                        title: NSLocalizedString("UPSCALING_MODELS"),
                        requires: "Reader.upscaleImages",
                        value: .page(.init(items: []))
                    ),
                    .init(
                        key: "Reader.upscaleMaxHeight",
                        title: NSLocalizedString("UPSCALE_MAX_IMAGE_HEIGHT"),
                        requires: "Reader.upscaleImages",
                        value: .stepper(.init(
                            minimumValue: 200,
                            maximumValue: 4000,
                            stepValue: 100
                        ))
                    )
                ]
            ))
        ),
        .init(
            title: NSLocalizedString("PAGED"),
            value: .group(.init(items: [
                .init(
                    key: "Reader.pagesToPreload",
                    title: NSLocalizedString("PAGES_TO_PRELOAD"),
                    value: .stepper(.init(minimumValue: 1, maximumValue: 10))
                ),
                .init(
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
                ),
                .init(
                    key: "Reader.pagedIsolateFirstPage",
                    title: NSLocalizedString("ISOLATE_FIRST_PAGE"),
                    notification: .init("Reader.pagedIsolateFirstPage"),
                    value: .toggle(.init())
                ),
                .init(
                    key: "Reader.splitWideImages",
                    title: NSLocalizedString("SPLIT_WIDE_IMAGES"),
                    notification: .init("Reader.splitWideImages"),
                    value: .toggle(.init())
                ),
                .init(
                    key: "Reader.reverseSplitOrder",
                    title: NSLocalizedString("REVERSE_SPLIT_ORDER"),
                    notification: .init("Reader.reverseSplitOrder"),
                    requires: "Reader.splitWideImages",
                    value: .toggle(.init())
                )
            ]))
        ),
        .init(
            title: NSLocalizedString("WEBTOON"),
            value: .group(.init(
                footer: NSLocalizedString("PILLARBOX_ORIENTATION_INFO"),
                items: [
                    .init(
                        key: "Reader.verticalInfiniteScroll",
                        title: NSLocalizedString("INFINITE_VERTICAL_SCROLL"),
                        value: .toggle(.init())
                    ),
                    .init(
                        key: "Reader.pillarbox",
                        title: NSLocalizedString("PILLARBOX"),
                        value: .toggle(.init())
                    ),
                    .init(
                        key: "Reader.pillarboxAmount",
                        title: NSLocalizedString("PILLARBOX_AMOUNT"),
                        requires: "Reader.pillarbox",
                        value: .stepper(.init(minimumValue: 0, maximumValue: 100, stepValue: 5))
                    ),
                    .init(
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
                ]
            ))
        )
    ]

    private static let advancedSettings: [Setting] = [
        .init(
            title: NSLocalizedString("LOGGING"),
            value: .group(.init(items: [
                .init(
                    key: "Logs.logServer",
                    title: NSLocalizedString("LOG_SERVER"),
                    value: .text(.init(
                        placeholder: "http://127.0.0.1",
                        autocapitalizationType: 0,
                        keyboardType: 3,
                        returnKeyType: 9,
                        autocorrectionDisabled: true,
                    ))
                ),
                .init(
                    key: "Logs.export",
                    title: NSLocalizedString("EXPORT_LOGS"),
                    value: .button(.init())
                ),
                .init(
                    key: "Logs.display",
                    title: NSLocalizedString("DISPLAY_LOGS"),
                    value: .button(.init())
                )
            ]))
        ),
        .init(
            title: NSLocalizedString("ADVANCED"),
            value: .group(.init(items: [
                .init(
                    key: "Advanced.clearTrackedManga",
                    title: NSLocalizedString("CLEAR_TRACKED_MANGA"),
                    value: .button(.init())
                ),
                .init(
                    key: "Advanced.clearNetworkCache",
                    title: NSLocalizedString("CLEAR_NETWORK_CACHE"),
                    value: .button(.init())
                ),
                .init(
                    key: "Advanced.clearReadHistory",
                    title: NSLocalizedString("CLEAR_READ_HISTORY"),
                    value: .button(.init())
                ),
                .init(
                    key: "Advanced.clearExcludingLibrary",
                    title: NSLocalizedString("CLEAR_EXCLUDING_LIBRARY"),
                    value: .button(.init())
                ),
                .init(
                    key: "Advanced.migrateHistory",
                    title: "Migrate Chapter History",
                    value: .button(.init())
                ),
                .init(
                    key: "Advanced.resetSettings",
                    title: NSLocalizedString("RESET_SETTINGS"),
                    value: .button(.init())
                ),
                .init(
                    key: "Advanced.reset",
                    title: NSLocalizedString("RESET"),
                    value: .button(.init())
                )
            ]))
        )
    ]
}

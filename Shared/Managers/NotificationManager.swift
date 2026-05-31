//
//  NotificationManager.swift
//  Aidoku
//

import Foundation
import UserNotifications

actor NotificationManager {
    static let shared = NotificationManager()

    struct NewChaptersSummary {
        let mangaIdentifier: MangaIdentifier
        let mangaTitle: String
        let chapterCount: Int
    }

    static let settingKey = "Library.notifyNewChapters"
    static let categoryIdentifier = "newChapters"
    static let threadIdentifier = "newChapters"
    static let sourceIdInfoKey = "sourceId"
    static let mangaIdInfoKey = "mangaId"

    nonisolated func isEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: Self.settingKey)
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
            case .authorized, .provisional:
                return true
            case .notDetermined:
                return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            default:
                return false
        }
    }

    func notifyNewChapters(_ summaries: [NewChaptersSummary]) async {
        guard !summaries.isEmpty, isEnabled() else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }

        for summary in summaries {
            let content = UNMutableNotificationContent()
            content.title = summary.mangaTitle
            content.body = Self.body(for: summary)
            content.sound = .default
            content.threadIdentifier = Self.threadIdentifier
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [
                Self.sourceIdInfoKey: summary.mangaIdentifier.sourceKey,
                Self.mangaIdInfoKey: summary.mangaIdentifier.mangaKey
            ]

            let identifier = "newChapters.\(summary.mangaIdentifier.sourceKey).\(summary.mangaIdentifier.mangaKey).\(Int(Date.now.timeIntervalSince1970))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

            try? await center.add(request)
        }
    }

    private static func body(for summary: NewChaptersSummary) -> String {
        if summary.chapterCount == 1 {
            return NSLocalizedString("1_NEW_CHAPTER_AVAILABLE")
        }
        return String(format: NSLocalizedString("X_NEW_CHAPTERS_AVAILABLE"), summary.chapterCount)
    }
}

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
    static let batchNotificationThreshold = 3

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

        if summaries.count > Self.batchNotificationThreshold {
            await Self.sendNotification(
                identifier: "newChapters.batch.\(Int(Date.now.timeIntervalSince1970))",
                title: NSLocalizedString("NEW_CHAPTERS_AVAILABLE"),
                body: String(format: NSLocalizedString("X_SERIES_HAVE_NEW_CHAPTERS"), summaries.count),
                center: center
            )
            return
        }

        for summary in summaries {
            let timestamp = Int(Date.now.timeIntervalSince1970)
            let identifier = "newChapters.\(summary.mangaIdentifier.sourceKey).\(summary.mangaIdentifier.mangaKey).\(timestamp)"
            await Self.sendNotification(
                identifier: identifier,
                title: summary.mangaTitle,
                body: Self.body(for: summary),
                userInfo: [
                    Self.sourceIdInfoKey: summary.mangaIdentifier.sourceKey,
                    Self.mangaIdInfoKey: summary.mangaIdentifier.mangaKey
                ],
                center: center
            )
        }
    }

    private static func sendNotification(
        identifier: String,
        title: String,
        body: String,
        userInfo: [AnyHashable: Any] = [:],
        center: UNUserNotificationCenter
    ) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = threadIdentifier
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = userInfo

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await center.add(request)
    }

    private static func body(for summary: NewChaptersSummary) -> String {
        if summary.chapterCount == 1 {
            return NSLocalizedString("1_NEW_CHAPTER_AVAILABLE")
        }
        return String(format: NSLocalizedString("X_NEW_CHAPTERS_AVAILABLE"), summary.chapterCount)
    }
}

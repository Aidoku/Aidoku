import Foundation

struct BookTranslationSettings: Equatable {
    static let changed = Notification.Name("Reader.bookTranslationChanged")
    static let enabledKey = "Reader.translation.enabled"
    static let automaticKey = "Reader.translation.automatic"
    static let aheadKey = "Reader.translation.ahead"
    static let sourceKey = "Reader.translation.source"
    static let targetKey = "Reader.translation.target"
    static let splitKey = "Reader.translation.split"

    let enabled: Bool
    let automatic: Bool
    let ahead: Bool
    let source: String
    let target: String
    let split: Bool

    init(defaults: UserDefaults = .standard) {
        enabled = defaults.bool(forKey: Self.enabledKey)
        automatic = defaults.bool(forKey: Self.automaticKey)
        ahead = defaults.bool(forKey: Self.aheadKey)
        source = defaults.string(forKey: Self.sourceKey) ?? ""
        target = defaults.string(forKey: Self.targetKey) ?? ""
        split = defaults.bool(forKey: Self.splitKey)
    }
}

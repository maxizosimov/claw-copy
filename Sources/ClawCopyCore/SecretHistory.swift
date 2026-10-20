import Foundation

/// Copies that password managers mark as concealed (or that were made while a password manager
/// was frontmost), kept for a short time only. Opt-in, memory only, never written to disk.
///
/// Entries expire `lifetime` seconds after they were first copied; restoring one doesn't extend
/// its life. Only `capacity` entries are kept.
public struct SecretHistory: Sendable {
    public struct Entry: Equatable, Sendable {
        public let text: String
        /// The app it was copied from, for display (e.g. "1Password").
        public let sourceName: String?
        public let copiedAt: Date
    }

    public static let defaultCapacity = 5
    /// What the menu shows instead of a secret: fixed length, so not even the length leaks.
    public static let mask = "••••••••"

    public private(set) var entries: [Entry] = []
    public let capacity: Int
    public var lifetime: TimeInterval

    public init(lifetime: TimeInterval, capacity: Int = SecretHistory.defaultCapacity) {
        self.lifetime = lifetime
        self.capacity = max(1, capacity)
    }

    public mutating func record(_ text: String, sourceName: String?, at now: Date) {
        purgeExpired(at: now)
        if let existing = entries.firstIndex(where: { $0.text == text }) {
            // Move to the top but keep the original copy time: restoring never extends a life.
            let entry = entries.remove(at: existing)
            entries.insert(entry, at: 0)
            return
        }
        entries.insert(Entry(text: text, sourceName: sourceName, copiedAt: now), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    public mutating func purgeExpired(at now: Date) {
        entries.removeAll { now.timeIntervalSince($0.copiedAt) >= lifetime }
    }

    public mutating func clear() {
        entries.removeAll()
    }

    public func secondsLeft(for entry: Entry, at now: Date) -> Int {
        max(0, Int((lifetime - now.timeIntervalSince(entry.copiedAt)).rounded(.up)))
    }

    /// e.g. "•••••••• · 1Password · 4:59 left", or "… · expired" once its time is up.
    public func menuTitle(for entry: Entry, at now: Date) -> String {
        let seconds = secondsLeft(for: entry, at: now)
        let source = entry.sourceName.map { " · " + HistoryMenuTitle.make($0, maxLength: 30) } ?? ""
        let left = seconds > 0 ? String(format: "%d:%02d left", seconds / 60, seconds % 60) : "expired"
        return Self.mask + source + " · " + left
    }
}

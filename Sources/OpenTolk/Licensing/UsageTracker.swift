import Foundation

final class UsageTracker {
    static let shared = UsageTracker()
    static let freeTierWordLimit = 5_000

    private let fileURL: URL
    private var usage: UsageData

    private struct UsageData: Codable {
        var monthKey: String // "2026-02" format
        var wordCount: Int
    }

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opentolk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("usage.json")
        usage = UsageTracker.load(from: fileURL)
        resetIfNewMonth()
    }

    func wordsUsed() -> Int {
        resetIfNewMonth()
        return usage.wordCount
    }

    func wordsRemaining() -> Int {
        if SubscriptionManager.shared.isPro { return Int.max }
        resetIfNewMonth()
        return max(0, UsageTracker.freeTierWordLimit - usage.wordCount)
    }

    func recordWords(count: Int) {
        resetIfNewMonth()
        usage.wordCount += count
        save()
    }

    private func resetIfNewMonth() {
        let currentMonth = Self.currentMonthKey()
        if usage.monthKey != currentMonth {
            usage = UsageData(monthKey: currentMonth, wordCount: 0)
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(usage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> UsageData {
        guard let data = try? Data(contentsOf: url),
              let usage = try? JSONDecoder().decode(UsageData.self, from: data)
        else {
            return UsageData(monthKey: currentMonthKey(), wordCount: 0)
        }
        return usage
    }

    private static func currentMonthKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: Date())
    }
}

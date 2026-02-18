import Foundation

struct HistoryEntry: Codable {
    let id: String
    let text: String
    let timestamp: Date

    init(text: String) {
        self.id = UUID().uuidString
        self.text = text
        self.timestamp = Date()
    }

    init(id: String, text: String, timestamp: Date) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
    }

    // Custom decoder to handle existing history.json files without id
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        text = try container.decode(String.self, forKey: .text)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}

final class HistoryManager {
    static let shared = HistoryManager()

    private let maxEntries = 50
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opentolk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
    }

    func add(text: String) {
        var entries = getAll()
        entries.insert(HistoryEntry(text: text), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
        NotificationCenter.default.post(name: .localDataChanged, object: nil)
    }

    /// Merge a history entry from server sync data.
    func mergeFromSync(_ entry: HistoryEntry) {
        var entries = getAll()
        if entries.contains(where: { $0.id == entry.id }) { return }
        entries.append(entry)
        entries.sort { $0.timestamp > $1.timestamp }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
    }

    func getAll() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    func clear() {
        save([])
    }

    private func save(_ entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

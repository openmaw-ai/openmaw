import Foundation

struct Snippet: Codable, Identifiable {
    let id: String
    var triggers: [String]
    var body: String
    var isEnabled: Bool
    var updatedAt: Date

    init(triggers: [String], body: String, isEnabled: Bool = true) {
        self.id = UUID().uuidString
        self.triggers = triggers
        self.body = body
        self.isEnabled = isEnabled
        self.updatedAt = Date()
    }

    init(id: String, triggers: [String], body: String, isEnabled: Bool, updatedAt: Date) {
        self.id = id
        self.triggers = triggers
        self.body = body
        self.isEnabled = isEnabled
        self.updatedAt = updatedAt
    }

    // Custom decoder to handle existing snippets.json files without updatedAt
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        triggers = try container.decode([String].self, forKey: .triggers)
        body = try container.decode(String.self, forKey: .body)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// Comma-separated display string for the UI.
    var triggersDisplay: String {
        triggers.joined(separator: ", ")
    }

    /// Parse a comma-separated string into trigger array.
    static func parseTriggers(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

final class SnippetManager {
    static let shared = SnippetManager()

    private(set) var snippets: [Snippet] = []
    private let fileManager = FileManager.default
    private let snippetsFileURL: URL

    private init() {
        let base = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".opentolk")
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        snippetsFileURL = base.appendingPathComponent("snippets.json")
        load()
    }

    // MARK: - Match

    /// Matches transcribed text against enabled snippets.
    /// Case-insensitive, start-of-text, longest-trigger-first.
    func match(_ text: String) -> Snippet? {
        guard Config.shared.snippetsEnabled else { return nil }

        // Strip punctuation that transcribers commonly add
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        let enabled = snippets.filter { $0.isEnabled }

        // Build (snippet, trigger) pairs sorted by trigger length descending
        var candidates: [(snippet: Snippet, trigger: String)] = []
        for snippet in enabled {
            for trigger in snippet.triggers {
                candidates.append((snippet, trigger.lowercased()))
            }
        }
        candidates.sort { $0.trigger.count > $1.trigger.count }

        for (snippet, lowerTrigger) in candidates {
            if cleaned == lowerTrigger { return snippet }

            guard cleaned.hasPrefix(lowerTrigger), cleaned.count > lowerTrigger.count else { continue }
            let charAfter = cleaned[cleaned.index(cleaned.startIndex, offsetBy: lowerTrigger.count)]
            if charAfter == " " || charAfter.isPunctuation {
                return snippet
            }
        }

        return nil
    }

    // MARK: - CRUD

    func add(triggers: [String], body: String) {
        let snippet = Snippet(triggers: triggers, body: body)
        snippets.append(snippet)
        save()
        notifySync()
    }

    func update(_ snippet: Snippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        var updated = snippet
        updated.updatedAt = Date()
        snippets[idx] = updated
        save()
        notifySync()
    }

    func delete(id: String) {
        snippets.removeAll { $0.id == id }
        save()
        notifySync()
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let idx = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[idx].isEnabled = enabled
        snippets[idx].updatedAt = Date()
        save()
        notifySync()
    }

    /// Delete without triggering sync (called from SyncManager during merge).
    func deleteWithoutSync(id: String) {
        snippets.removeAll { $0.id == id }
        save()
    }

    /// Merge a snippet from server sync data.
    func mergeFromSync(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            // Only update if server version is newer
            if snippet.updatedAt > snippets[idx].updatedAt {
                snippets[idx] = snippet
                save()
            }
        } else {
            snippets.append(snippet)
            save()
        }
    }

    private func notifySync() {
        NotificationCenter.default.post(name: .localDataChanged, object: nil)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: snippetsFileURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return }
        snippets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: snippetsFileURL, options: .atomic)
    }

    func reload() {
        load()
    }
}

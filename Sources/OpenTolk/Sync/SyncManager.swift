import Foundation
import AppKit

extension Notification.Name {
    static let syncDataChanged = Notification.Name("syncDataChanged")
    static let localDataChanged = Notification.Name("localDataChanged")
}

final class SyncManager {
    static let shared = SyncManager()

    private static let baseURL = Config.apiBaseURL
    private static let lastSyncTimeKey = "sync_last_server_time"
    private static let debounceInterval: TimeInterval = 0.5
    private static let foregroundSyncGap: TimeInterval = 5 * 60 // 5 minutes

    private var debounceTimer: Timer?
    private var lastBackgroundedAt: Date?
    private var isSyncing = false
    private var localChangeObserver: Any?
    private var foregroundObserver: Any?

    private(set) var lastSyncTime: Date?

    private init() {
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Listen for local data changes (debounced sync trigger)
        localChangeObserver = NotificationCenter.default.addObserver(
            forName: .localDataChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleDebouncedSync()
        }

        // Listen for app becoming active after being in background
        foregroundObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let lastBg = self.lastBackgroundedAt,
               Date().timeIntervalSince(lastBg) > Self.foregroundSyncGap {
                self.syncIfNeeded()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastBackgroundedAt = Date()
        }
    }

    // MARK: - Public API

    func syncIfNeeded() {
        guard AuthManager.shared.isSignedIn, SubscriptionManager.shared.isPro else { return }

        Task {
            await performSync()
        }
    }

    // MARK: - Debounced Sync

    private func scheduleDebouncedSync() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { [weak self] _ in
            self?.syncIfNeeded()
        }
    }

    // MARK: - Sync Logic

    private func performSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await pull()
            try await push()
        } catch {
            // Silently fail — sync is best-effort
            print("Sync error: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull

    private func pull() async throws {
        let since = UserDefaults.standard.string(forKey: Self.lastSyncTimeKey) ?? "1970-01-01T00:00:00Z"

        guard let url = URL(string: "\(Self.baseURL)/sync/pull?since=\(since)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await AuthManager.shared.authenticatedRequest(request)

        if response.statusCode == 403 {
            // Pro required — stop syncing silently
            return
        }

        guard response.statusCode == 200 else { return }

        let pullResponse = try JSONDecoder().decode(SyncPullResponse.self, from: data)

        // Merge items into local stores
        await MainActor.run {
            mergeItems(pullResponse.items)
            UserDefaults.standard.set(pullResponse.serverTime, forKey: Self.lastSyncTimeKey)
            lastSyncTime = ISO8601DateFormatter().date(from: pullResponse.serverTime)
        }
    }

    // MARK: - Push

    private struct SyncPushBody: Encodable {
        let items: [SyncItem]
    }

    private func push() async throws {
        let pendingItems = collectPendingChanges()
        guard !pendingItems.isEmpty else { return }

        guard let url = URL(string: "\(Self.baseURL)/sync/push") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SyncPushBody(items: pendingItems))

        let (data, response) = try await AuthManager.shared.authenticatedRequest(request)

        if response.statusCode == 403 {
            return // Pro required
        }

        guard response.statusCode == 200 else { return }

        let pushResponse = try JSONDecoder().decode(SyncPushResponse.self, from: data)

        // Handle conflicts by merging server data
        if !pushResponse.conflicts.isEmpty {
            await MainActor.run {
                mergeConflicts(pushResponse.conflicts)
            }
        }

        UserDefaults.standard.set(pushResponse.serverTime, forKey: Self.lastSyncTimeKey)
        lastSyncTime = ISO8601DateFormatter().date(from: pushResponse.serverTime)
    }

    // MARK: - Collect Local Changes

    private func collectPendingChanges() -> [SyncItem] {
        var items: [SyncItem] = []
        let formatter = ISO8601DateFormatter()

        // Snippets
        for snippet in SnippetManager.shared.snippets {
            let data: [String: Any] = [
                "id": snippet.id,
                "triggers": snippet.triggers,
                "body": snippet.body,
                "isEnabled": snippet.isEnabled,
            ]
            items.append(SyncItem(
                itemType: "snippet",
                itemId: snippet.id,
                data: SyncItemData(data),
                deleted: false,
                updatedAt: formatter.string(from: snippet.updatedAt)
            ))
        }

        // History
        for entry in HistoryManager.shared.getAll() {
            let data: [String: Any] = [
                "id": entry.id,
                "text": entry.text,
                "timestamp": formatter.string(from: entry.timestamp),
            ]
            items.append(SyncItem(
                itemType: "history",
                itemId: entry.id,
                data: SyncItemData(data),
                deleted: false,
                updatedAt: formatter.string(from: entry.timestamp)
            ))
        }

        // Config (sync-relevant settings only)
        let config = Config.shared
        let configData: [String: Any] = [
            "language": config.language,
            "groqModel": config.groqModel,
            "silenceThresholdRMS": config.silenceThresholdRMS,
            "silenceDuration": config.silenceDuration,
            "holdThresholdMs": config.holdThresholdMs,
            "maxRecordingDuration": config.maxRecordingDuration,
            "pluginsEnabled": config.pluginsEnabled,
            "snippetsEnabled": config.snippetsEnabled,
        ]
        items.append(SyncItem(
            itemType: "config",
            itemId: "user_config",
            data: SyncItemData(configData),
            deleted: false,
            updatedAt: formatter.string(from: config.configUpdatedAt)
        ))

        return items
    }

    // MARK: - Merge Server Data

    private func mergeItems(_ items: [SyncItem]) {
        for item in items {
            switch item.itemType {
            case "snippet":
                mergeSnippet(item)
            case "history":
                mergeHistoryEntry(item)
            case "config":
                mergeConfig(item)
            default:
                break
            }
        }
    }

    private func mergeSnippet(_ item: SyncItem) {
        guard let dict = item.data.value as? [String: Any] else { return }

        if item.deleted {
            SnippetManager.shared.deleteWithoutSync(id: item.itemId)
            return
        }

        guard let triggers = dict["triggers"] as? [String],
              let body = dict["body"] as? String,
              let isEnabled = dict["isEnabled"] as? Bool
        else { return }

        let formatter = ISO8601DateFormatter()
        let updatedAt = formatter.date(from: item.updatedAt) ?? Date()

        let snippet = Snippet(
            id: item.itemId,
            triggers: triggers,
            body: body,
            isEnabled: isEnabled,
            updatedAt: updatedAt
        )
        SnippetManager.shared.mergeFromSync(snippet)
    }

    private func mergeHistoryEntry(_ item: SyncItem) {
        guard let dict = item.data.value as? [String: Any],
              let text = dict["text"] as? String,
              let timestampStr = dict["timestamp"] as? String,
              let timestamp = ISO8601DateFormatter().date(from: timestampStr)
        else { return }

        let entry = HistoryEntry(id: item.itemId, text: text, timestamp: timestamp)
        HistoryManager.shared.mergeFromSync(entry)
    }

    private func mergeConfig(_ item: SyncItem) {
        guard let dict = item.data.value as? [String: Any] else { return }

        let config = Config.shared
        if let language = dict["language"] as? String { config.language = language }
        if let groqModel = dict["groqModel"] as? String { config.groqModel = groqModel }
        if let threshold = dict["silenceThresholdRMS"] as? Double { config.silenceThresholdRMS = Float(threshold) }
        if let duration = dict["silenceDuration"] as? Double { config.silenceDuration = duration }
        if let holdMs = dict["holdThresholdMs"] as? Int { config.holdThresholdMs = holdMs }
        if let maxDuration = dict["maxRecordingDuration"] as? Double { config.maxRecordingDuration = maxDuration }
        if let plugins = dict["pluginsEnabled"] as? Bool { config.pluginsEnabled = plugins }
        if let snippets = dict["snippetsEnabled"] as? Bool { config.snippetsEnabled = snippets }
        // selectedMicrophoneID is device-specific — excluded from sync
    }

    private func mergeConflicts(_ conflicts: [SyncConflict]) {
        for conflict in conflicts {
            let item = SyncItem(
                itemType: conflict.itemType,
                itemId: conflict.itemId,
                data: conflict.serverData,
                deleted: false,
                updatedAt: conflict.serverUpdatedAt
            )
            switch conflict.itemType {
            case "snippet":
                mergeSnippet(item)
            case "history":
                mergeHistoryEntry(item)
            case "config":
                mergeConfig(item)
            default:
                break
            }
        }
    }
}

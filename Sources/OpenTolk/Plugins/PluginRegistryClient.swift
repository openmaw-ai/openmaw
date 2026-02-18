import Foundation

// MARK: - Registry Models

struct RegistryPlugin: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String
    let author: String
    let categories: [String]?
    let url: String           // download URL (raw GitHub URL to .tolkplugin file or zip)
    let homepage: String?
    let featured: Bool?

    /// Whether this is a single-file plugin (JSON) or a folder plugin (zip).
    var isSingleFile: Bool {
        url.hasSuffix(".tolkplugin") || url.hasSuffix(".json")
    }
}

struct RegistryIndex: Codable {
    let plugins: [RegistryPlugin]
}

struct PluginUpdateInfo {
    let id: String
    let latestVersion: String
    let url: String
}

// MARK: - GitHub-Backed Registry Client

final class PluginRegistryClient {
    static let shared = PluginRegistryClient()

    /// Base raw GitHub URL for the community plugins repo.
    /// Change this to your actual repo: https://raw.githubusercontent.com/opentolk/community-plugins/main
    private let indexURL: String

    private var cachedIndex: RegistryIndex?
    private var cacheDate: Date?
    private let cacheTTL: TimeInterval = 300  // 5 minutes

    init(indexURL: String = "https://raw.githubusercontent.com/opentolk/community-plugins/main/plugins.json") {
        self.indexURL = indexURL
    }

    // MARK: - Fetch Index

    private func fetchIndex(forceRefresh: Bool = false) async throws -> RegistryIndex {
        // Return cached if fresh
        if !forceRefresh, let cached = cachedIndex, let date = cacheDate,
           Date().timeIntervalSince(date) < cacheTTL {
            return cached
        }

        guard let url = URL(string: indexURL) else {
            throw PluginRegistryError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw PluginRegistryError.fetchFailed("HTTP \(statusCode)")
        }

        let index = try JSONDecoder().decode(RegistryIndex.self, from: data)
        cachedIndex = index
        cacheDate = Date()
        return index
    }

    // MARK: - Featured

    func featured() async throws -> [RegistryPlugin] {
        let index = try await fetchIndex()
        return index.plugins.filter { $0.featured == true }
    }

    // MARK: - Search

    func search(query: String? = nil, category: String? = nil) async throws -> [RegistryPlugin] {
        let index = try await fetchIndex()
        var results = index.plugins

        if let query, !query.isEmpty {
            let lower = query.lowercased()
            results = results.filter {
                $0.name.lowercased().contains(lower) ||
                $0.description.lowercased().contains(lower) ||
                $0.id.lowercased().contains(lower)
            }
        }

        if let category, !category.isEmpty {
            results = results.filter {
                $0.categories?.contains(category) == true
            }
        }

        return results
    }

    // MARK: - Check Updates

    func checkUpdates(installed: [(id: String, version: String)]) async throws -> [PluginUpdateInfo] {
        let index = try await fetchIndex(forceRefresh: true)
        var updates: [PluginUpdateInfo] = []

        for (id, currentVersion) in installed {
            if let registryPlugin = index.plugins.first(where: { $0.id == id }),
               registryPlugin.version != currentVersion {
                updates.append(PluginUpdateInfo(
                    id: id,
                    latestVersion: registryPlugin.version,
                    url: registryPlugin.url
                ))
            }
        }

        return updates
    }

    // MARK: - Install

    func install(plugin: RegistryPlugin) async throws -> String {
        guard let url = URL(string: plugin.url) else {
            throw PluginInstallerError.invalidURL
        }
        return try await PluginInstaller.install(from: url)
    }
}

// MARK: - Errors

enum PluginRegistryError: LocalizedError {
    case invalidURL
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid registry URL"
        case .fetchFailed(let msg): return "Failed to fetch plugin registry: \(msg)"
        }
    }
}

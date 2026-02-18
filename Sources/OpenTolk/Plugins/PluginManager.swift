import Foundation

final class PluginManager {
    static let shared = PluginManager()

    private(set) var plugins: [LoadedPlugin] = []

    private let fileManager = FileManager.default
    private let pluginsDir: URL
    private let settingsDir: URL
    private let dataDir: URL
    private let enabledKey = "enabledPlugins"

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    static let pluginsDidReload = Notification.Name("PluginManagerPluginsDidReload")

    private init() {
        let base = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".opentolk")
        pluginsDir = base.appendingPathComponent("plugins")
        settingsDir = base.appendingPathComponent("plugin-settings")
        dataDir = base.appendingPathComponent("plugin-data")

        ensureDirectories()
        reloadPlugins()
        startWatching()
    }

    // MARK: - Directory Setup

    private func ensureDirectories() {
        for dir in [pluginsDir, settingsDir, dataDir] {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Plugin Discovery & Loading

    func reloadPlugins() {
        plugins = []

        guard let contents = try? fileManager.contentsOfDirectory(
            at: pluginsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }

        let enabledIDs = enabledPluginIDs()

        for item in contents {
            guard item.pathExtension == "tolkplugin" else { continue }

            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: item.path, isDirectory: &isDir)

            if isDir.boolValue {
                loadDirectoryPlugin(item, enabledIDs: enabledIDs)
            } else {
                loadSingleFilePlugin(item, enabledIDs: enabledIDs)
            }
        }

        plugins.sort { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }

        NotificationCenter.default.post(name: Self.pluginsDidReload, object: nil)
    }

    // MARK: - Directory Plugin Loading

    private func loadDirectoryPlugin(_ folder: URL, enabledIDs: Set<String>) {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }

        do {
            let data = try Data(contentsOf: manifestURL)
            let decoder = JSONDecoder()
            let manifest = try decoder.decode(PluginManifest.self, from: data)

            guard validateManifest(manifest, in: folder) else {
                print("[PluginManager] Invalid manifest in \(folder.lastPathComponent)")
                return
            }

            let isEnabled = enabledIDs.contains(manifest.id)
            plugins.append(LoadedPlugin(manifest: manifest, directoryURL: folder, isEnabled: isEnabled))
        } catch {
            print("[PluginManager] Failed to load \(folder.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Single-File Plugin Loading

    private func loadSingleFilePlugin(_ file: URL, enabledIDs: Set<String>) {
        do {
            let data = try Data(contentsOf: file)
            let decoder = JSONDecoder()
            let manifest = try decoder.decode(PluginManifest.self, from: data)

            guard validateManifest(manifest, in: file.deletingLastPathComponent()) else {
                print("[PluginManager] Invalid single-file manifest: \(file.lastPathComponent)")
                return
            }

            // Single-file plugins use the plugins directory as their "directory"
            let isEnabled = enabledIDs.contains(manifest.id)
            plugins.append(LoadedPlugin(manifest: manifest, directoryURL: file.deletingLastPathComponent(), isEnabled: isEnabled))
        } catch {
            print("[PluginManager] Failed to load single-file plugin \(file.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - Hot Reload (File Watching)

    private func startWatching() {
        let fd = open(pluginsDir.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[PluginManager] Failed to open plugins directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.debounceReload()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        directoryWatcher = source
    }

    private func debounceReload() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.reloadPlugins()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    // MARK: - Validation

    private func validateManifest(_ manifest: PluginManifest, in folder: URL) -> Bool {
        guard !manifest.id.isEmpty, !manifest.name.isEmpty else { return false }

        // Check for path traversal in id
        if manifest.id.contains("..") || manifest.id.contains("/") { return false }

        // If script type with command, verify script file exists
        if case .script(let config) = manifest.execution, let command = config.command {
            let scriptName = (command as NSString).lastPathComponent
            let scriptURL = folder.appendingPathComponent(scriptName)
            if !fileManager.fileExists(atPath: scriptURL.path) {
                print("[PluginManager] Script not found: \(scriptName) in \(folder.lastPathComponent)")
                return false
            }
        }

        return true
    }

    // MARK: - Enable / Disable

    func enabledPluginIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: enabledKey) ?? []
        return Set(array)
    }

    func setEnabled(_ enabled: Bool, for pluginID: String) {
        var ids = enabledPluginIDs()
        if enabled {
            ids.insert(pluginID)
        } else {
            ids.remove(pluginID)
        }
        UserDefaults.standard.set(Array(ids), forKey: enabledKey)

        if let idx = plugins.firstIndex(where: { $0.manifest.id == pluginID }) {
            plugins[idx].isEnabled = enabled
        }
    }

    func isEnabled(_ pluginID: String) -> Bool {
        enabledPluginIDs().contains(pluginID)
    }

    var enabledPlugins: [LoadedPlugin] {
        plugins.filter { $0.isEnabled }
    }

    // MARK: - Plugin Settings Storage

    private func settingsURL(for pluginID: String) -> URL {
        settingsDir.appendingPathComponent("\(pluginID).json")
    }

    func loadSettings(for pluginID: String) -> [String: String] {
        let url = settingsURL(for: pluginID)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    func saveSettings(_ settings: [String: String], for pluginID: String, manifest: PluginManifest) {
        var fileSettings = settings
        let secretKeys = Set((manifest.settings ?? []).filter { $0.type == .secret }.map { $0.key })

        for (key, value) in settings {
            if secretKeys.contains(key) {
                KeychainHelper.save(key: "plugin.\(pluginID).\(key)", value: value)
                fileSettings.removeValue(forKey: key)
            }
        }

        let url = settingsURL(for: pluginID)
        if let data = try? JSONEncoder().encode(fileSettings) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func resolvedSettings(for plugin: LoadedPlugin) -> [String: String] {
        var settings = loadSettings(for: plugin.manifest.id)
        let secretKeys = (plugin.manifest.settings ?? []).filter { $0.type == .secret }.map { $0.key }

        for key in secretKeys {
            if let value = KeychainHelper.load(key: "plugin.\(plugin.manifest.id).\(key)") {
                settings[key] = value
            }
        }

        for setting in plugin.manifest.settings ?? [] {
            if settings[setting.key] == nil, let defaultValue = setting.default {
                settings[setting.key] = "\(defaultValue.value)"
            }
        }

        return settings
    }

    // MARK: - Plugin Data Directory

    func dataDirectory(for pluginID: String) -> URL {
        let dir = dataDir.appendingPathComponent(pluginID)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Uninstall

    func uninstall(pluginID: String) {
        guard let plugin = plugins.first(where: { $0.manifest.id == pluginID }) else { return }

        // Remove plugin folder
        try? fileManager.removeItem(at: plugin.directoryURL)

        // Remove settings file
        try? fileManager.removeItem(at: settingsURL(for: pluginID))

        // Remove secrets from Keychain
        for setting in plugin.manifest.settings ?? [] where setting.type == .secret {
            KeychainHelper.delete(key: "plugin.\(pluginID).\(setting.key)")
        }

        // Remove data directory
        let pluginDataDir = dataDir.appendingPathComponent(pluginID)
        try? fileManager.removeItem(at: pluginDataDir)

        // Remove from enabled list
        setEnabled(false, for: pluginID)

        // Clear conversation state
        ConversationManager.shared.clear(for: pluginID)

        reloadPlugins()
    }

    // MARK: - Plugins Directory Access

    var pluginsDirectoryURL: URL { pluginsDir }
}

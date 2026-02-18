import AppKit
import Foundation

enum PluginInstallerError: LocalizedError {
    case invalidURL
    case downloadFailed(String)
    case extractionFailed
    case noPluginFound
    case invalidManifest(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid plugin URL"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .extractionFailed: return "Failed to extract plugin archive"
        case .noPluginFound: return "No .tolkplugin found in archive"
        case .invalidManifest(let msg): return "Invalid manifest: \(msg)"
        }
    }
}

enum PluginInstaller {

    /// Handles the opentolk://install-plugin?url=... URL scheme.
    @MainActor
    static func handleInstallURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "install-plugin",
              let pluginURLString = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let pluginURL = URL(string: pluginURLString)
        else {
            showAlert(title: "Installation Failed", message: "Invalid install URL.")
            return
        }

        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Install Plugin?"
        alert.informativeText = "Do you want to install a plugin from:\n\(pluginURL.absoluteString)\n\nOnly install plugins from sources you trust."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            do {
                let name = try await install(from: pluginURL)
                await MainActor.run {
                    showAlert(title: "Plugin Installed", message: "\"\(name)\" has been installed. Enable it in Settings → Plugins.")
                }
            } catch {
                await MainActor.run {
                    showAlert(title: "Installation Failed", message: error.localizedDescription)
                }
            }
        }
    }

    /// Downloads and installs a plugin from a URL. Returns the plugin name.
    /// Supports: zip archives, single JSON files (.tolkplugin), and GitHub repo URLs.
    static func install(from url: URL) async throws -> String {
        // Detect GitHub repo URL and resolve to latest release
        let resolvedURL = try await resolveGitHubURL(url)

        // Check if it's a single-file JSON plugin
        if resolvedURL.pathExtension == "tolkplugin" || resolvedURL.pathExtension == "json" {
            return try await installSingleFile(from: resolvedURL)
        }

        return try await installFromZip(from: resolvedURL)
    }

    // MARK: - Single-File Install

    private static func installSingleFile(from url: URL) async throws -> String {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse == nil || (200...299).contains(httpResponse!.statusCode) else {
            throw PluginInstallerError.downloadFailed("HTTP \(httpResponse!.statusCode)")
        }

        let data = try Data(contentsOf: tempURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

        guard !manifest.id.isEmpty, !manifest.name.isEmpty else {
            throw PluginInstallerError.invalidManifest("Missing id or name")
        }
        guard !manifest.id.contains(".."), !manifest.id.contains("/") else {
            throw PluginInstallerError.invalidManifest("Invalid plugin id")
        }

        // Determine filename
        let filename = "\(manifest.id).tolkplugin"
        let dest = PluginManager.shared.pluginsDirectoryURL.appendingPathComponent(filename)

        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try data.write(to: dest, options: .atomic)

        PluginManager.shared.reloadPlugins()
        return manifest.name
    }

    // MARK: - Zip Install

    private static func installFromZip(from url: URL) async throws -> String {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        let httpResponse = response as? HTTPURLResponse
        guard httpResponse == nil || (200...299).contains(httpResponse!.statusCode) else {
            throw PluginInstallerError.downloadFailed("HTTP \(httpResponse!.statusCode)")
        }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        // Extract zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", tempURL.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PluginInstallerError.extractionFailed
        }

        // Find .tolkplugin in extracted contents
        let extracted = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey])

        // Check top level
        if let pluginFolder = extracted.first(where: { $0.pathExtension == "tolkplugin" }) {
            return try installPluginFolder(pluginFolder)
        }

        // Check one level deeper (zip might have a wrapper folder)
        for dir in extracted {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let inner = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            if let found = inner.first(where: { $0.pathExtension == "tolkplugin" }) {
                return try installPluginFolder(found)
            }
        }

        throw PluginInstallerError.noPluginFound
    }

    // MARK: - GitHub URL Resolution

    private static func resolveGitHubURL(_ url: URL) async throws -> URL {
        let host = url.host?.lowercased() ?? ""
        guard host == "github.com" else { return url }

        // Convert github.com/user/repo to API call for latest release
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return url }

        let owner = pathComponents[0]
        let repo = pathComponents[1]

        // If URL already points to a release asset, use it directly
        if pathComponents.contains("releases") && pathComponents.contains("download") {
            return url
        }

        // Fetch latest release
        let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
            throw PluginInstallerError.downloadFailed("Could not find GitHub release")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            throw PluginInstallerError.downloadFailed("Invalid GitHub release response")
        }

        // Find .zip asset containing "tolkplugin"
        if let asset = assets.first(where: {
            let name = ($0["name"] as? String ?? "").lowercased()
            return name.hasSuffix(".zip") || name.contains("tolkplugin")
        }), let downloadURL = asset["browser_download_url"] as? String,
           let assetURL = URL(string: downloadURL) {
            return assetURL
        }

        // Fallback: use zipball URL
        if let zipballURL = json["zipball_url"] as? String, let zipURL = URL(string: zipballURL) {
            return zipURL
        }

        throw PluginInstallerError.downloadFailed("No suitable download found in GitHub release")
    }

    // MARK: - Install Plugin Folder

    private static func installPluginFolder(_ folder: URL) throws -> String {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PluginInstallerError.invalidManifest("manifest.json not found")
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

        guard !manifest.id.isEmpty, !manifest.name.isEmpty else {
            throw PluginInstallerError.invalidManifest("Missing id or name")
        }
        guard !manifest.id.contains(".."), !manifest.id.contains("/") else {
            throw PluginInstallerError.invalidManifest("Invalid plugin id")
        }

        // Copy to plugins directory
        let dest = PluginManager.shared.pluginsDirectoryURL.appendingPathComponent(folder.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: folder, to: dest)

        PluginManager.shared.reloadPlugins()
        return manifest.name
    }

    // MARK: - Alerts

    @MainActor
    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

import Foundation

final class PluginEventBus {
    static let shared = PluginEventBus()

    enum Event: String {
        case transcriptionComplete = "transcription.complete"
        case pluginOutput = "plugin.output"
        case appLaunch = "app.launch"
        case conversationStart = "conversation.start"
    }

    private init() {}

    /// Emits an event. Plugins subscribed to this event via `events` in their manifest
    /// will be triggered asynchronously (non-blocking).
    func emit(event: Event, data: String?) {
        let plugins = PluginManager.shared.enabledPlugins

        for plugin in plugins {
            // Only script plugins can subscribe to events via environment vars
            guard case .script(let config) = plugin.manifest.execution else { continue }
            guard config.command != nil || config.inline != nil else { continue }

            // Check if plugin has events subscription in categories (convention)
            // For now, trigger all script plugins that have a matching event handler
            let eventScriptPath = plugin.directoryURL.appendingPathComponent("on-\(event.rawValue.replacingOccurrences(of: ".", with: "-")).sh")
            guard FileManager.default.fileExists(atPath: eventScriptPath.path) else { continue }

            // Run event handler asynchronously
            Task.detached {
                let process = Process()
                let interpreter = "/bin/bash"
                process.executableURL = URL(fileURLWithPath: interpreter)
                process.arguments = [eventScriptPath.path]
                process.currentDirectoryURL = plugin.directoryURL

                var env = ProcessInfo.processInfo.environment
                env["OPENTOLK_EVENT_TYPE"] = event.rawValue
                if let data {
                    env["OPENTOLK_EVENT_DATA"] = data
                }
                process.environment = env

                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    print("[PluginEventBus] Failed to run event handler for \(plugin.manifest.id): \(error.localizedDescription)")
                }
            }
        }
    }
}

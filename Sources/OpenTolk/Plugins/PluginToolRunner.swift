import AppKit
import Foundation

/// Executes tools called by AI plugins during conversation.
enum PluginToolRunner {

    struct ToolCall {
        let name: String
        let arguments: [String: Any]
    }

    struct ToolResult {
        let name: String
        let content: String
    }

    /// Runs a tool and returns the result text.
    static func run(tool: ToolConfig, call: ToolCall, plugin: LoadedPlugin) async throws -> ToolResult {
        switch tool.type {
        case .builtin:
            return try await runBuiltin(tool: tool, call: call, plugin: plugin)
        case .script:
            return try await runScript(tool: tool, call: call, plugin: plugin)
        }
    }

    // MARK: - Builtin Tools

    private static func runBuiltin(tool: ToolConfig, call: ToolCall, plugin: LoadedPlugin) async throws -> ToolResult {
        switch call.name {
        case "web_search":
            let query = call.arguments["query"] as? String ?? ""
            let result = try await webSearch(query: query)
            return ToolResult(name: call.name, content: result)

        case "read_clipboard":
            let content = await MainActor.run {
                NSPasteboard.general.string(forType: .string) ?? ""
            }
            return ToolResult(name: call.name, content: content)

        case "paste":
            let text = call.arguments["text"] as? String ?? ""
            await MainActor.run { PasteManager.paste(text) }
            return ToolResult(name: call.name, content: "Pasted successfully")

        case "run_plugin":
            let pluginID = tool.config?["plugin_id"] ?? call.arguments["plugin_id"] as? String ?? ""
            let input = call.arguments["input"] as? String ?? ""
            let result = try await runPlugin(pluginID: pluginID, input: input)
            return ToolResult(name: call.name, content: result)

        default:
            return ToolResult(name: call.name, content: "Unknown builtin tool: \(call.name)")
        }
    }

    // MARK: - Script Tools

    private static func runScript(tool: ToolConfig, call: ToolCall, plugin: LoadedPlugin) async throws -> ToolResult {
        guard let command = tool.command else {
            return ToolResult(name: call.name, content: "Error: Script tool missing command")
        }

        let scriptPath = plugin.directoryURL.appendingPathComponent(command).path
        let timeout: TimeInterval = 30

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            process.currentDirectoryURL = plugin.directoryURL
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Pass arguments as JSON on stdin
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
            if let argsData = try? JSONSerialization.data(withJSONObject: call.arguments) {
                stdinPipe.fileHandleForWriting.write(argsData)
            }
            stdinPipe.fileHandleForWriting.closeFile()

            var env = ProcessInfo.processInfo.environment
            env["OPENTOLK_TOOL_NAME"] = call.name
            if let argsJSON = try? JSONSerialization.data(withJSONObject: call.arguments),
               let argsString = String(data: argsJSON, encoding: .utf8) {
                env["OPENTOLK_TOOL_ARGS"] = argsString
            }
            process.environment = env

            let timeoutItem = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            process.terminationHandler = { proc in
                timeoutItem.cancel()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if proc.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ToolResult(name: call.name, content: "Error: \(stderr)"))
                    return
                }

                continuation.resume(returning: ToolResult(name: call.name, content: stdout))
            }

            do {
                try process.run()
            } catch {
                timeoutItem.cancel()
                continuation.resume(returning: ToolResult(name: call.name, content: "Error: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Helpers

    private static func webSearch(query: String) async throws -> String {
        // Simple web search using DuckDuckGo instant answer API
        guard !query.isEmpty else { return "No query provided" }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1") else {
            return "Invalid search query"
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "No results found"
        }

        var results: [String] = []
        if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
            results.append(abstract)
        }
        if let relatedTopics = json["RelatedTopics"] as? [[String: Any]] {
            for topic in relatedTopics.prefix(3) {
                if let text = topic["Text"] as? String {
                    results.append(text)
                }
            }
        }

        return results.isEmpty ? "No results found for: \(query)" : results.joined(separator: "\n\n")
    }

    private static func runPlugin(pluginID: String, input: String) async throws -> String {
        guard let plugin = PluginManager.shared.enabledPlugins.first(where: { $0.manifest.id == pluginID }) else {
            return "Plugin not found: \(pluginID)"
        }

        let syntheticMatch = PluginMatch(
            plugin: plugin,
            trigger: plugin.manifest.trigger,
            triggerWord: "",
            input: input,
            rawInput: input
        )

        let result = try await PluginRunner.run(match: syntheticMatch)
        switch result {
        case .complete(let pluginResult):
            return pluginResult.text
        case .stream(let stream, _):
            var collected = ""
            for try await event in stream {
                if case .textDelta(let delta) = event {
                    collected += delta
                }
            }
            return collected
        }
    }
}

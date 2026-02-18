import Foundation

enum CrashReporter {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".opentolk/crashes", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let log = """
            OpenTolk Crash Report
            Date: \(ISO8601DateFormatter().string(from: Date()))
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack:
            \(exception.callStackSymbols.joined(separator: "\n"))
            """

            let fileName = "crash-\(ISO8601DateFormatter().string(from: Date())).log"
                .replacingOccurrences(of: ":", with: "-")
            let fileURL = dir.appendingPathComponent(fileName)
            try? log.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static func previousCrashLogs() -> [URL] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".opentolk/crashes", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
    }
}

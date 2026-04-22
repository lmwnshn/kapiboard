import Foundation
#if os(macOS)
import Darwin
#endif

public actor SnapshotStore {
    public static let fileName = "dashboard-snapshot.json"

    private let fileURL: URL

    public init(fileURL: URL = SnapshotStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() async -> DashboardSnapshot {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder.dashboard.decode(DashboardSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }

    public func save(_ snapshot: DashboardSnapshot) async throws {
        let data = try JSONEncoder.dashboard.encode(snapshot)

        for url in Self.writeURLs(primaryURL: fileURL) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }

    public static func defaultFileURL() -> URL {
        if let localSharedURL = ProcessInfo.processInfo.environment["KAPIBOARD_SNAPSHOT_DIR"] {
            return URL(fileURLWithPath: localSharedURL, isDirectory: true)
                .appendingPathComponent(fileName)
        }

        if ProcessInfo.processInfo.processName.contains("WidgetExtension") {
            if let sandboxHome = ProcessInfo.processInfo.environment["HOME"] {
                return groupContainerFileURL(home: sandboxHome)
            }

            if let appGroupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.me.wanshenl.KapiBoard"
            ) {
                return appGroupURL.appendingPathComponent(fileName)
            }
        }

        if let home = realHomeDirectory() ?? ProcessInfo.processInfo.environment["HOME"] {
            return groupContainerFileURL(home: home)
        }

        if let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.me.wanshenl.KapiBoard"
        ) {
            return appGroupURL.appendingPathComponent(fileName)
        }

        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KapiBoard")
            .appendingPathComponent(fileName)
    }

    private static func writeURLs(primaryURL: URL) -> [URL] {
        var paths = [primaryURL.path]

        if !ProcessInfo.processInfo.processName.contains("WidgetExtension"),
           let home = realHomeDirectory() ?? ProcessInfo.processInfo.environment["HOME"] {
            paths.append(contentsOf: [
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.WidgetExtension").path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.DetailWidgetExtension").path
            ])
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            guard !seen.contains(path) else {
                return nil
            }
            seen.insert(path)
            return URL(fileURLWithPath: path)
        }
    }

    private static func groupContainerFileURL(home: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent("group.me.wanshenl.KapiBoard")
            .appendingPathComponent(fileName)
    }

    private static func widgetContainerFileURL(home: String, bundleIdentifier: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("Data")
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent("group.me.wanshenl.KapiBoard")
            .appendingPathComponent(fileName)
    }

    private static func realHomeDirectory() -> String? {
#if os(macOS)
        guard let passwd = getpwuid(getuid()),
              let directory = passwd.pointee.pw_dir else {
            return nil
        }
        return String(cString: directory)
#else
        return nil
#endif
    }
}

extension JSONEncoder {
    static var dashboard: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var dashboard: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

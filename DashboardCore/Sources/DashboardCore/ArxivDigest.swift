import Foundation
#if os(macOS)
import Darwin
#endif

public struct ArxivDigest: Codable, Equatable, Sendable {
    public var category: String
    public var source: String
    public var pulledAt: Date?
    public var summarizedAt: Date?
    public var targetDate: String?
    public var dateLabel: String
    public var paperCount: Int?
    public var categoryCounts: [ArxivCategoryCount]?
    public var digest: [String]
    public var items: [ArxivDigestItem]
    public var status: String

    public init(
        category: String = "cs.DB",
        source: String = "https://rss.arxiv.org/rss/cs.DB",
        pulledAt: Date? = nil,
        summarizedAt: Date? = nil,
        targetDate: String? = nil,
        dateLabel: String = "",
        paperCount: Int? = nil,
        categoryCounts: [ArxivCategoryCount]? = nil,
        digest: [String] = [],
        items: [ArxivDigestItem] = [],
        status: String = "notConfigured"
    ) {
        self.category = category
        self.source = source
        self.pulledAt = pulledAt
        self.summarizedAt = summarizedAt
        self.targetDate = targetDate
        self.dateLabel = dateLabel
        self.paperCount = paperCount
        self.categoryCounts = categoryCounts
        self.digest = digest
        self.items = items
        self.status = status
    }

    public static let empty = ArxivDigest()
}

public struct ArxivCategoryCount: Codable, Identifiable, Equatable, Sendable {
    public var category: String
    public var count: Int

    public var id: String {
        category
    }

    public init(category: String, count: Int) {
        self.category = category
        self.count = count
    }
}

public struct ArxivDigestItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var url: String
    public var firstAuthor: String
    public var firstAuthorInstitution: String?
    public var authors: [String]
    public var authorInstitutions: [String]?
    public var category: String?
    public var summary: String
    public var publishedAt: Date?

    public init(
        id: String,
        title: String,
        url: String,
        firstAuthor: String = "",
        firstAuthorInstitution: String? = nil,
        authors: [String] = [],
        authorInstitutions: [String]? = nil,
        category: String? = nil,
        summary: String = "",
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.firstAuthor = firstAuthor
        self.firstAuthorInstitution = firstAuthorInstitution
        self.authors = authors
        self.authorInstitutions = authorInstitutions
        self.category = category
        self.summary = summary
        self.publishedAt = publishedAt
    }
}

public enum ArxivDigestStore {
    public static let fileName = "cs.DB-summary.json"
    public static let appGroupIdentifier = "group.me.wanshenl.KapiBoard"

    public static func load() -> ArxivDigest {
        for url in readURLs() {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(ArxivDigest.self, from: data)
            } catch {
                continue
            }
        }

        return .empty
    }

    public static func save(_ digest: ArxivDigest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(digest)
        var savedAtLeastOneURL = false
        var lastError: Error?

        for url in writeURLs() {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                savedAtLeastOneURL = true
            } catch {
                lastError = error
            }
        }

        if !savedAtLeastOneURL, let lastError {
            throw lastError
        }
    }

    public static func primaryFileURL() -> URL {
        if let configuredPath = ProcessInfo.processInfo.environment["KAPIBOARD_ARXIV_DIGEST_PATH"],
           !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }

        let home = realHomeDirectory() ?? ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return userFileURL(home: home)
    }

    public static func writeURLs() -> [URL] {
        var paths = [primaryFileURL().path]

        if let home = realHomeDirectory() ?? ProcessInfo.processInfo.environment["HOME"] {
            paths.append(contentsOf: [
                groupContainerFileURL(home: home).path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.WidgetExtension").path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.DetailWidgetExtension").path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.ArxivWidgetExtension").path
            ])
        }

        return uniqueURLs(paths: paths)
    }

    private static func readURLs() -> [URL] {
        var paths: [String] = []

        if let configuredPath = ProcessInfo.processInfo.environment["KAPIBOARD_ARXIV_DIGEST_PATH"],
           !configuredPath.isEmpty {
            paths.append(configuredPath)
        }

        if ProcessInfo.processInfo.processName.contains("WidgetExtension"),
           let sandboxHome = ProcessInfo.processInfo.environment["HOME"] {
            paths.append(groupContainerFileURL(home: sandboxHome).path)
        }

        if let home = realHomeDirectory() ?? ProcessInfo.processInfo.environment["HOME"] {
            paths.append(contentsOf: [
                userFileURL(home: home).path,
                groupContainerFileURL(home: home).path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.WidgetExtension").path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.DetailWidgetExtension").path,
                widgetContainerFileURL(home: home, bundleIdentifier: "me.wanshenl.KapiBoard.ArxivWidgetExtension").path
            ])
        }

        return uniqueURLs(paths: paths)
    }

    private static func userFileURL(home: String) -> URL {
        URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".kapiboard")
            .appendingPathComponent("arxiv")
            .appendingPathComponent(fileName)
    }

    private static func groupContainerFileURL(home: String) -> URL {
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return containerURL
                .appendingPathComponent("arxiv")
                .appendingPathComponent(fileName)
        }

        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent(appGroupIdentifier)
            .appendingPathComponent("arxiv")
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
            .appendingPathComponent(appGroupIdentifier)
            .appendingPathComponent("arxiv")
            .appendingPathComponent(fileName)
    }

    private static func uniqueURLs(paths: [String]) -> [URL] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard !seen.contains(path) else {
                return nil
            }
            seen.insert(path)
            return URL(fileURLWithPath: path)
        }
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

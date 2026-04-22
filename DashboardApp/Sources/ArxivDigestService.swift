#if canImport(DashboardCore)
import DashboardCore
#endif
import Foundation

struct ArxivDigestService {
    enum ServiceError: LocalizedError {
        case scriptMissing(URL)
        case scriptFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case let .scriptMissing(url):
                "arXiv updater script not found at \(url.path)"
            case let .scriptFailed(status, message):
                "arXiv updater failed with exit \(status): \(message)"
            }
        }
    }

    private let calendar = Calendar.current

    func defaultDate() -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date()) ?? Date())
    }

    func canMoveNext(from date: Date) -> Bool {
        calendar.startOfDay(for: date) < defaultDate()
    }

    func move(_ date: Date, days: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: date) ?? date)
    }

    func load(date: Date) async throws -> ArxivDigest {
        let target = Self.targetDateString(from: date)
        if let digest = loadCachedDigest(targetDate: target) {
            return digest
        }

        let outputURL = dailyFileURL(targetDate: target)
        try await runUpdater(targetDate: target, outputURL: outputURL)
        return loadCachedDigest(targetDate: target) ?? .empty
    }

    func loadMostRecentNonEmptyPriorDigest(maxLookbackDays: Int = 7) async throws -> (Date, ArxivDigest) {
        let start = defaultDate()
        var lastEmpty: (Date, ArxivDigest)?

        for offset in 0..<maxLookbackDays {
            let date = move(start, days: -offset)
            let digest = try await load(date: date)
            if !digest.items.isEmpty {
                try? ArxivDigestStore.save(digest)
                return (date, digest)
            }
            lastEmpty = (date, digest)
        }

        if let lastEmpty {
            return lastEmpty
        }

        return (start, .empty)
    }

    static func targetDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func loadCachedDigest(targetDate: String) -> ArxivDigest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in candidateReadURLs(targetDate: targetDate) {
            do {
                let data = try Data(contentsOf: url)
                let digest = try decoder.decode(ArxivDigest.self, from: data)
                if digest.status == "ready", digest.targetDate == targetDate {
                    if digestNeedsCategoryRefresh(digest) {
                        continue
                    }
                    return digest
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func digestNeedsCategoryRefresh(_ digest: ArxivDigest) -> Bool {
        guard !digest.items.isEmpty else {
            return false
        }

        guard let categoryCounts = digest.categoryCounts, !categoryCounts.isEmpty else {
            return true
        }

        return digest.items.contains { item in
            item.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    private func candidateReadURLs(targetDate: String) -> [URL] {
        [
            dailyFileURL(targetDate: targetDate),
            ArxivDigestStore.primaryFileURL()
        ]
    }

    private func dailyFileURL(targetDate: String) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".kapiboard")
            .appendingPathComponent("arxiv")
            .appendingPathComponent("daily")
            .appendingPathComponent("\(targetDate).json")
    }

    private func runUpdater(targetDate: String, outputURL: URL) async throws {
        let scriptURL = updaterScriptURL()
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw ServiceError.scriptMissing(scriptURL)
        }

        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [
                scriptURL.path,
                "--force",
                "--target-date",
                targetDate,
                "--output",
                outputURL.path
            ]

            let errorPipe = Pipe()
            process.standardError = errorPipe
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ServiceError.scriptFailed(process.terminationStatus, message)
            }
        }.value
    }

    private func updaterScriptURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["KAPIBOARD_ARXIV_UPDATER"],
           !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }

        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("scripts")
            .appendingPathComponent("update_arxiv_digest.py"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        return sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts")
            .appendingPathComponent("update_arxiv_digest.py")
    }
}

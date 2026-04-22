#if canImport(DashboardCore)
import DashboardCore
#endif
import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

@Observable
@MainActor
final class DashboardViewModel {
    var snapshot: DashboardSnapshot = .empty
    var isRefreshing = false
    var googleCalendarConfigured = false
    var googleCalendarConnected = false
    var googleCalendarAuthError: String?
    var arxivDigest: ArxivDigest = .empty
    var arxivSelectedDate: Date
    var arxivIsLoading = false
    var arxivError: String?

    private let provider: DashboardDataProvider
    private let store: SnapshotStore
    private let configuration: DashboardConfiguration
    private let arxivService = ArxivDigestService()
    private let minimumRefreshInterval: TimeInterval = 60
    private let lastRefreshStartedAtKey = "lastRefreshStartedAt"
    private var lastRefreshStartedAt: Date?

    init(
        provider: DashboardDataProvider? = nil,
        store: SnapshotStore = SnapshotStore(),
        configuration: DashboardConfiguration = DashboardConfiguration(
            gmailEnabled: true
        )
    ) {
        self.provider = provider ?? CompositeDashboardProvider(
            calendarProvider: GoogleCalendarProvider {
                await GoogleOAuthManager.shared.validAccessToken()
            },
            mailProvider: GmailAPIProvider {
                await GoogleOAuthManager.shared.validAccessToken()
            }
        )
        self.store = store
        self.configuration = configuration
        self.arxivSelectedDate = arxivService.defaultDate()
    }

    func load() async {
        await refreshGoogleCalendarState()
        snapshot = await store.load()
        await loadMostRecentArxivDigest()
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }
        let now = Date()
        if let effectiveLastRefreshStartedAt,
           now.timeIntervalSince(effectiveLastRefreshStartedAt) < minimumRefreshInterval {
            return
        }

        isRefreshing = true
        recordRefreshStarted(at: now)
        defer {
            isRefreshing = false
        }
        let currentSnapshot = snapshot
        var nextSnapshot = await provider.fetch(configuration: configuration)
        if nextSnapshot.markets.quotes.isEmpty,
           !currentSnapshot.markets.quotes.isEmpty {
            var retainedMarkets = currentSnapshot.markets
            retainedMarkets.checkedAt = nextSnapshot.markets.checkedAt
            retainedMarkets.status = nextSnapshot.markets.status
            nextSnapshot.markets = retainedMarkets
        }
        snapshot = nextSnapshot
        try? await store.save(nextSnapshot)
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
#endif
        await refreshGoogleCalendarState()
    }

    private var effectiveLastRefreshStartedAt: Date? {
        lastRefreshStartedAt ?? UserDefaults.standard.object(forKey: lastRefreshStartedAtKey) as? Date
    }

    private func recordRefreshStarted(at date: Date) {
        lastRefreshStartedAt = date
        UserDefaults.standard.set(date, forKey: lastRefreshStartedAtKey)
    }

    func connectGoogleCalendar() async {
        googleCalendarAuthError = nil
        do {
            try await GoogleOAuthManager.shared.authorize()
            await refreshGoogleCalendarState()
            await refresh()
        } catch {
            googleCalendarAuthError = error.localizedDescription
            await refreshGoogleCalendarState()
        }
    }

    func disconnectGoogleCalendar() async {
        googleCalendarAuthError = nil
        do {
            try await GoogleOAuthManager.shared.signOut()
        } catch {
            googleCalendarAuthError = error.localizedDescription
        }
        await refreshGoogleCalendarState()
        await refresh()
    }

    func refreshGoogleCalendarState() async {
        googleCalendarConfigured = await GoogleOAuthManager.shared.isConfigured
        googleCalendarConnected = await GoogleOAuthManager.shared.hasStoredToken
    }

    func startRefreshLoop() async {
        await load()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            await refresh()
        }
    }

    var canMoveArxivNext: Bool {
        arxivService.canMoveNext(from: arxivSelectedDate)
    }

    func previousArxivDate() async {
        arxivSelectedDate = arxivService.move(arxivSelectedDate, days: -1)
        await loadArxivDigestForSelectedDate()
    }

    func nextArxivDate() async {
        guard canMoveArxivNext else {
            return
        }
        arxivSelectedDate = arxivService.move(arxivSelectedDate, days: 1)
        await loadArxivDigestForSelectedDate()
    }

    func loadArxivDigestForSelectedDate() async {
        guard !arxivIsLoading else {
            return
        }

        arxivIsLoading = true
        arxivError = nil
        defer {
            arxivIsLoading = false
        }

        do {
            arxivDigest = try await arxivService.load(date: arxivSelectedDate)
        } catch {
            arxivDigest = .empty
            arxivError = error.localizedDescription
        }
    }

    func loadMostRecentArxivDigest() async {
        guard !arxivIsLoading else {
            return
        }

        arxivIsLoading = true
        arxivError = nil
        defer {
            arxivIsLoading = false
        }

        do {
            let result = try await arxivService.loadMostRecentNonEmptyPriorDigest()
            arxivSelectedDate = result.0
            arxivDigest = result.1
        } catch {
            arxivDigest = .empty
            arxivError = error.localizedDescription
        }
    }
}

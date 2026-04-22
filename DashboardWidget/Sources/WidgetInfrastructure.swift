#if canImport(DashboardCore)
import DashboardCore
#endif
import Foundation
import WidgetKit

struct DashboardEntry: TimelineEntry {
    let date: Date
    let snapshot: DashboardSnapshot
}

struct DashboardTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DashboardEntry {
        DashboardEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DashboardEntry) -> Void) {
        completion(DashboardEntry(date: Date(), snapshot: Self.loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DashboardEntry>) -> Void) {
        let entry = DashboardEntry(date: Date(), snapshot: Self.loadSnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private static func loadSnapshot() -> DashboardSnapshot {
        do {
            let data = try Data(contentsOf: SnapshotStore.defaultFileURL())
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(DashboardSnapshot.self, from: data)
        } catch {
            return .empty
        }
    }
}

enum WidgetLinks {
    static let gmailInbox = source(URL(string: "https://mail.google.com/mail/u/0/#inbox")!)
    static let googleCalendar = source(URL(string: "https://calendar.google.com/calendar/u/0/r")!)

    static func source(_ url: URL) -> URL {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return URL(string: "https://www.google.com")!
        }

        var components = URLComponents()
        components.scheme = "kapiboard"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString)
        ]
        return components.url ?? url
    }

    static func yahooFinance(symbol: String) -> URL {
        let escaped = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        return source(URL(string: "https://finance.yahoo.com/quote/\(escaped)")!)
    }

    static func weather(for weather: WeatherSnapshot) -> URL {
        let query = "weather \(weather.locationName)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "weather"
        return source(URL(string: "https://www.google.com/search?q=\(query)")!)
    }
}

extension CalendarItem {
    var widgetURL: URL? {
        url.flatMap(URL.init(string:)).map(WidgetLinks.source)
    }
}

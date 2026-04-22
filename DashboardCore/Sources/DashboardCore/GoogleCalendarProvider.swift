import Foundation

public struct GoogleCalendarProvider: CalendarProviding {
    private let session: URLSession
    private let accessTokenProvider: @Sendable () async -> String?

    public init(
        session: URLSession = .shared,
        accessTokenProvider: @escaping @Sendable () async -> String?
    ) {
        self.session = session
        self.accessTokenProvider = accessTokenProvider
    }

    public func fetchCalendar() async -> CalendarSnapshot {
        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            return CalendarSnapshot(
                today: [],
                upcoming: [],
                checkedAt: nil,
                source: .google,
                status: .unavailable("Connect Google to load Calendar.")
            )
        }

        do {
            let visibleCalendars = try await fetchVisibleCalendars(accessToken: accessToken)
            guard !visibleCalendars.isEmpty else {
                return CalendarSnapshot(today: [], upcoming: [], checkedAt: Date(), source: .google, status: .ready)
            }

            let calendar = Calendar.current
            let now = Date()
            let todayInterval = calendar.dateInterval(of: .day, for: now)
            let start = todayInterval?.start ?? now
            let todayEnd = todayInterval?.end ?? now.addingTimeInterval(24 * 60 * 60)
            let upcomingEnd = calendar.date(byAdding: .day, value: 7, to: todayEnd) ?? todayEnd.addingTimeInterval(7 * 24 * 60 * 60)

            let calendarResults = await withTaskGroup(of: GoogleCalendarFetchResult.self) { group in
                for googleCalendar in visibleCalendars {
                    group.addTask {
                        (try? await fetchEvents(
                            calendar: googleCalendar,
                            start: start,
                            end: upcomingEnd,
                            accessToken: accessToken
                        )) ?? GoogleCalendarFetchResult(items: [], sourceUpdatedAt: nil)
                    }
                }

                var results: [GoogleCalendarFetchResult] = []
                for await calendarResult in group {
                    results.append(calendarResult)
                }
                return results
            }
            let items = calendarResults
                .flatMap(\.items)
                .sorted { $0.startDate < $1.startDate }
            let sourceUpdatedAt = calendarResults
                .compactMap(\.sourceUpdatedAt)
                .max()

            return CalendarSnapshot(
                today: items.filter { $0.startDate < todayEnd },
                upcoming: items.filter { $0.startDate >= todayEnd },
                checkedAt: Date(),
                sourceUpdatedAt: sourceUpdatedAt,
                source: .google,
                status: .ready
            )
        } catch {
            return CalendarSnapshot(
                today: [],
                upcoming: [],
                checkedAt: Date(),
                source: .google,
                status: .unavailable(error.localizedDescription)
            )
        }
    }

    private func fetchVisibleCalendars(accessToken: String) async throws -> [GoogleCalendarListItem] {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")
        components?.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "showHidden", value: "false")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let response = try await googleRequest(GoogleCalendarListResponse.self, url: url, accessToken: accessToken)
        return response.items.filter { $0.selected == true }
    }

    private func fetchEvents(
        calendar googleCalendar: GoogleCalendarListItem,
        start: Date,
        end: Date,
        accessToken: String
    ) async throws -> GoogleCalendarFetchResult {
        var allItems: [GoogleEvent] = []
        var pageToken: String?

        repeat {
            let response = try await fetchEventPage(
                calendar: googleCalendar,
                start: start,
                end: end,
                pageToken: pageToken,
                accessToken: accessToken
            )
            allItems.append(contentsOf: response.items)
            pageToken = response.nextPageToken
        } while pageToken != nil

        let items: [CalendarItem] = allItems.compactMap { event in
            guard event.status != "cancelled",
                  let startDate = event.start.eventDate,
                  let endDate = event.end.eventDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: startDate) else {
                return nil
            }

            return CalendarItem(
                id: event.id,
                title: event.summary ?? "(No title)",
                startDate: startDate,
                endDate: endDate,
                calendarTitle: googleCalendar.summary,
                isAllDay: event.start.date != nil,
                url: event.htmlLink
            )
        }
        let sourceUpdatedAt = allItems.compactMap(\.updatedDate).max()
        return GoogleCalendarFetchResult(items: items, sourceUpdatedAt: sourceUpdatedAt)
    }

    private func fetchEventPage(
        calendar googleCalendar: GoogleCalendarListItem,
        start: Date,
        end: Date,
        pageToken: String?,
        accessToken: String
    ) async throws -> GoogleEventsResponse {
        let encodedID = googleCalendar.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? googleCalendar.id
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events")
        var queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: Self.rfc3339String(from: start)),
            URLQueryItem(name: "timeMax", value: Self.rfc3339String(from: end)),
            URLQueryItem(name: "maxResults", value: "2500")
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        return try await googleRequest(GoogleEventsResponse.self, url: url, accessToken: accessToken)
    }

    private func googleRequest<T: Decodable>(_ type: T.Type, url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw DashboardHTTPError(
                statusCode: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        return try Self.decoder.decode(T.self, from: data)
    }

    private static func rfc3339String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static let decoder = JSONDecoder()
}

private struct GoogleCalendarListResponse: Decodable {
    var items: [GoogleCalendarListItem]
}

private struct GoogleCalendarListItem: Decodable {
    var id: String
    var summary: String
    var selected: Bool?
}

private struct GoogleEventsResponse: Decodable {
    var items: [GoogleEvent]
    var nextPageToken: String?
}

private struct GoogleCalendarFetchResult {
    var items: [CalendarItem]
    var sourceUpdatedAt: Date?
}

private struct GoogleEvent: Decodable {
    var id: String
    var status: String?
    var summary: String?
    var htmlLink: String?
    var updated: String?
    var start: GoogleEventDate
    var end: GoogleEventDate

    var updatedDate: Date? {
        updated.flatMap(Self.parseDateTime)
    }

    private static func parseDateTime(_ value: String) -> Date? {
        let rfc3339WithFractionalSeconds = ISO8601DateFormatter()
        rfc3339WithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let rfc3339 = ISO8601DateFormatter()
        rfc3339.formatOptions = [.withInternetDateTime]

        return rfc3339WithFractionalSeconds.date(from: value) ?? rfc3339.date(from: value)
    }
}

private struct GoogleEventDate: Decodable {
    var date: Date?
    var dateTime: Date?

    var eventDate: Date? {
        dateTime ?? date
    }

    enum CodingKeys: String, CodingKey {
        case date
        case dateTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date).flatMap(Self.parseDate)
        dateTime = try container.decodeIfPresent(String.self, forKey: .dateTime).flatMap(Self.parseDateTime)
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func parseDateTime(_ value: String) -> Date? {
        let rfc3339WithFractionalSeconds = ISO8601DateFormatter()
        rfc3339WithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let rfc3339 = ISO8601DateFormatter()
        rfc3339.formatOptions = [.withInternetDateTime]

        return rfc3339WithFractionalSeconds.date(from: value) ?? rfc3339.date(from: value)
    }
}

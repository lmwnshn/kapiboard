import Foundation

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var calendar: CalendarSnapshot
    public var reminders: ReminderSnapshot
    public var mail: MailSnapshot
    public var weather: WeatherSnapshot
    public var markets: MarketSnapshot
    public var clocks: [ClockSnapshot]

    public init(
        generatedAt: Date = Date(),
        calendar: CalendarSnapshot = .empty,
        reminders: ReminderSnapshot = .empty,
        mail: MailSnapshot = .empty,
        weather: WeatherSnapshot = .empty,
        markets: MarketSnapshot = .empty,
        clocks: [ClockSnapshot] = []
    ) {
        self.generatedAt = generatedAt
        self.calendar = calendar
        self.reminders = reminders
        self.mail = mail
        self.weather = weather
        self.markets = markets
        self.clocks = clocks
    }

    public static var empty: DashboardSnapshot {
        DashboardSnapshot()
    }
}

public struct CalendarSnapshot: Codable, Equatable, Sendable {
    public var today: [CalendarItem]
    public var upcoming: [CalendarItem]
    public var checkedAt: Date?
    public var sourceUpdatedAt: Date?
    public var source: CalendarSource?
    public var status: SourceStatus?

    public init(
        today: [CalendarItem],
        upcoming: [CalendarItem],
        checkedAt: Date? = nil,
        sourceUpdatedAt: Date? = nil,
        source: CalendarSource? = nil,
        status: SourceStatus? = nil
    ) {
        self.today = today
        self.upcoming = upcoming
        self.checkedAt = checkedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.source = source
        self.status = status
    }

    public static let empty = CalendarSnapshot(today: [], upcoming: [], checkedAt: nil, sourceUpdatedAt: nil, source: nil, status: .notConfigured)
}

public struct CalendarItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var calendarTitle: String
    public var isAllDay: Bool
    public var url: String?

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        calendarTitle: String,
        isAllDay: Bool,
        url: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendarTitle = calendarTitle
        self.isAllDay = isAllDay
        self.url = url
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDate
        case endDate
        case calendarTitle
        case isAllDay
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        calendarTitle = try container.decode(String.self, forKey: .calendarTitle)
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }
}

public enum CalendarSource: String, Codable, Equatable, Sendable {
    case eventKit
    case google
}

public struct ReminderSnapshot: Codable, Equatable, Sendable {
    public var dueSoon: [ReminderItem]

    public static let empty = ReminderSnapshot(dueSoon: [])
}

public struct ReminderItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var dueDate: Date?
    public var listTitle: String
}

public struct MailSnapshot: Codable, Equatable, Sendable {
    public var unreadCount: Int
    public var messages: [MailItem]
    public var status: SourceStatus

    public static let empty = MailSnapshot(unreadCount: 0, messages: [], status: .notConfigured)
}

public struct MailItem: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var from: String
    public var subject: String
    public var snippet: String
    public var receivedAt: Date?
}

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var locationName: String
    public var temperature: Double?
    public var apparentTemperature: Double?
    public var precipitation: Double?
    public var humidity: Double?
    public var windSpeed: Double?
    public var airQualityIndex: Double?
    public var uvIndex: Double?
    public var conditionCode: Int?
    public var hourly: [HourlyWeather]
    public var sunrise: Date?
    public var sunset: Date?
    public var status: SourceStatus

    public static let empty = WeatherSnapshot(
        locationName: "Not configured",
        temperature: nil,
        apparentTemperature: nil,
        precipitation: nil,
        humidity: nil,
        windSpeed: nil,
        airQualityIndex: nil,
        uvIndex: nil,
        conditionCode: nil,
        hourly: [],
        sunrise: nil,
        sunset: nil,
        status: .notConfigured
    )
}

public struct HourlyWeather: Codable, Identifiable, Equatable, Sendable {
    public var id: String { time.ISO8601Format() }
    public var time: Date
    public var temperature: Double
    public var precipitationProbability: Double?
    public var conditionCode: Int?
}

public struct MarketSnapshot: Codable, Equatable, Sendable {
    public var quotes: [MarketQuote]
    public var checkedAt: Date?
    public var status: SourceStatus

    public init(
        quotes: [MarketQuote],
        checkedAt: Date? = nil,
        status: SourceStatus
    ) {
        self.quotes = quotes
        self.checkedAt = checkedAt
        self.status = status
    }

    public static let empty = MarketSnapshot(quotes: [], checkedAt: nil, status: .notConfigured)
}

public struct MarketQuote: Codable, Identifiable, Equatable, Sendable {
    public var id: String { symbol }
    public var symbol: String
    public var name: String
    public var price: Double?
    public var change: Double?
    public var changePercent: Double?
    public var sparkline: [Double]
    public var updatedAt: Date?
}

public struct ClockSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: String { timeZoneIdentifier }
    public var city: String
    public var timeZoneIdentifier: String
    public var currentDate: Date
}

public enum SourceStatus: Codable, Equatable, Sendable {
    case ready
    case notConfigured
    case unavailable(String)
}

public struct DashboardHTTPError: LocalizedError, Sendable {
    public var statusCode: Int
    public var body: String

    public init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    public var errorDescription: String? {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            return "HTTP \(statusCode)"
        }
        return "HTTP \(statusCode): \(trimmedBody)"
    }
}

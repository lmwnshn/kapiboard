import Foundation

public protocol DashboardDataProvider: Sendable {
    func fetch(configuration: DashboardConfiguration) async -> DashboardSnapshot
}

public struct CompositeDashboardProvider: DashboardDataProvider {
    private let calendarProvider: CalendarProviding
    private let reminderProvider: ReminderProviding
    private let weatherProvider: WeatherProviding
    private let marketProvider: MarketProviding
    private let mailProvider: MailProviding
    private let clockProvider: ClockProviding

    public init(
        calendarProvider: CalendarProviding? = nil,
        reminderProvider: ReminderProviding? = nil,
        weatherProvider: WeatherProviding = OpenMeteoWeatherProvider(),
        marketProvider: MarketProviding = YahooChartMarketProvider(),
        mailProvider: MailProviding = GmailAPIProvider(),
        clockProvider: ClockProviding = SystemClockProvider()
    ) {
        let eventKitProvider = EventKitAgendaProvider()
        self.calendarProvider = calendarProvider ?? eventKitProvider
        self.reminderProvider = reminderProvider ?? eventKitProvider
        self.weatherProvider = weatherProvider
        self.marketProvider = marketProvider
        self.mailProvider = mailProvider
        self.clockProvider = clockProvider
    }

    public func fetch(configuration: DashboardConfiguration) async -> DashboardSnapshot {
        async let calendar = calendarProvider.fetchCalendar()
        async let reminders = reminderProvider.fetchReminders()
        async let weather = weatherProvider.fetchWeather(location: configuration.weatherLocation)
        async let markets = marketProvider.fetchQuotes(symbols: configuration.marketSymbols)
        async let mail = mailProvider.fetchUnreadSummary(enabled: configuration.gmailEnabled)
        async let clocks = clockProvider.fetchClocks(cities: configuration.clockCities)

        return DashboardSnapshot(
            generatedAt: Date(),
            calendar: await calendar,
            reminders: await reminders,
            mail: await mail,
            weather: await weather,
            markets: await markets,
            clocks: await clocks
        )
    }
}

public protocol CalendarProviding: Sendable {
    func fetchCalendar() async -> CalendarSnapshot
}

public protocol ReminderProviding: Sendable {
    func fetchReminders() async -> ReminderSnapshot
}

public protocol WeatherProviding: Sendable {
    func fetchWeather(location: WeatherLocation) async -> WeatherSnapshot
}

public protocol MarketProviding: Sendable {
    func fetchQuotes(symbols: [String]) async -> MarketSnapshot
}

public protocol MailProviding: Sendable {
    func fetchUnreadSummary(enabled: Bool) async -> MailSnapshot
}

public protocol ClockProviding: Sendable {
    func fetchClocks(cities: [ClockCity]) async -> [ClockSnapshot]
}

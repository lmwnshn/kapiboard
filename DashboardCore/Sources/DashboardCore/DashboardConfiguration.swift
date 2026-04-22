import Foundation

public struct DashboardConfiguration: Codable, Equatable, Sendable {
    public var weatherLocation: WeatherLocation
    public var marketSymbols: [String]
    public var clockCities: [ClockCity]
    public var gmailEnabled: Bool

    public init(
        weatherLocation: WeatherLocation = .pittsburgh,
        marketSymbols: [String] = ["VXUS", "VTI", "SGD=X"],
        clockCities: [ClockCity] = ClockCity.defaults,
        gmailEnabled: Bool = false
    ) {
        self.weatherLocation = weatherLocation
        self.marketSymbols = marketSymbols
        self.clockCities = clockCities
        self.gmailEnabled = gmailEnabled
    }
}

public struct WeatherLocation: Codable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZone: String

    public static let pittsburgh = WeatherLocation(
        name: "Pittsburgh",
        latitude: 40.4406,
        longitude: -79.9959,
        timeZone: "America/New_York"
    )
}

public struct ClockCity: Codable, Equatable, Sendable {
    public var name: String
    public var timeZoneIdentifier: String

    public static let defaults = [
        ClockCity(name: "New York", timeZoneIdentifier: "America/New_York"),
        ClockCity(name: "San Francisco", timeZoneIdentifier: "America/Los_Angeles"),
        ClockCity(name: "Singapore", timeZoneIdentifier: "Asia/Singapore")
    ]
}

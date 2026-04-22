import Foundation

public struct SystemClockProvider: ClockProviding {
    public init() {}

    public func fetchClocks(cities: [ClockCity]) async -> [ClockSnapshot] {
        let now = Date()
        return cities.map {
            ClockSnapshot(city: $0.name, timeZoneIdentifier: $0.timeZoneIdentifier, currentDate: now)
        }
    }
}

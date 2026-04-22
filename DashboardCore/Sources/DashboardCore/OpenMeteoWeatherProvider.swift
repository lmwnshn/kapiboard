import Foundation

public struct OpenMeteoWeatherProvider: WeatherProviding {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchWeather(location: WeatherLocation) async -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,precipitation,relative_humidity_2m,wind_speed_10m,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,uv_index"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: location.timeZone),
            URLQueryItem(name: "forecast_days", value: "2")
        ]

        guard let url = components?.url else {
            return .empty
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try OpenMeteoResponse.decoder.decode(OpenMeteoResponse.self, from: data)
            let hourly = response.hourly?.items(limit: 48) ?? []
            let airQualityIndex = await fetchAirQualityIndex(location: location)

            return WeatherSnapshot(
                locationName: location.name,
                temperature: response.current?.temperature,
                apparentTemperature: response.current?.apparentTemperature,
                precipitation: response.current?.precipitation,
                humidity: response.current?.humidity,
                windSpeed: response.current?.windSpeed,
                airQualityIndex: airQualityIndex,
                uvIndex: response.hourly?.uvIndex.compactMap { $0 }.first,
                conditionCode: response.current?.weatherCode,
                hourly: hourly,
                sunrise: response.daily?.sunrise.first,
                sunset: response.daily?.sunset.first,
                status: .ready
            )
        } catch {
            return WeatherSnapshot(
                locationName: location.name,
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
                status: .unavailable(error.localizedDescription)
            )
        }
    }

    private func fetchAirQualityIndex(location: WeatherLocation) async -> Double? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "us_aqi"),
            URLQueryItem(name: "timezone", value: location.timeZone)
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try OpenMeteoAirQualityResponse.decoder.decode(OpenMeteoAirQualityResponse.self, from: data)
            return response.current?.usAQI
        } catch {
            return nil
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    var current: Current?
    var hourly: Hourly?
    var daily: Daily?

    struct Current: Decodable {
        var temperature: Double?
        var apparentTemperature: Double?
        var precipitation: Double?
        var humidity: Double?
        var windSpeed: Double?
        var weatherCode: Int?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitation
            case humidity = "relative_humidity_2m"
            case windSpeed = "wind_speed_10m"
            case weatherCode = "weather_code"
        }
    }

    struct Hourly: Decodable {
        var time: [Date]
        var temperature: [Double]
        var precipitationProbability: [Double?]
        var weatherCode: [Int?]
        var uvIndex: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
            case uvIndex = "uv_index"
        }

        func items(limit: Int) -> [HourlyWeather] {
            Array(time.indices.prefix(limit)).map { index in
                HourlyWeather(
                    time: time[index],
                    temperature: temperature[safe: index] ?? 0,
                    precipitationProbability: precipitationProbability[safe: index] ?? nil,
                    conditionCode: weatherCode[safe: index] ?? nil
                )
            }
        }
    }

    struct Daily: Decodable {
        var sunrise: [Date]
        var sunset: [Date]
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        let isoWithMinutes = DateFormatter()
        isoWithMinutes.locale = Locale(identifier: "en_US_POSIX")
        isoWithMinutes.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let isoWithSeconds = DateFormatter()
        isoWithSeconds.locale = Locale(identifier: "en_US_POSIX")
        isoWithSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = isoWithSeconds.date(from: value) ?? isoWithMinutes.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Open-Meteo date: \(value)"
            )
        }
        return decoder
    }
}

private struct OpenMeteoAirQualityResponse: Decodable {
    var current: Current?

    struct Current: Decodable {
        var usAQI: Double?

        enum CodingKeys: String, CodingKey {
            case usAQI = "us_aqi"
        }
    }

    static var decoder: JSONDecoder {
        OpenMeteoResponse.decoder
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

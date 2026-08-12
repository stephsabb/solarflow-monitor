import Foundation
import CoreLocation

struct WeatherLocation: Equatable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
}

actor OpenMeteoService {
    private struct GeocodingResponse: Decodable {
        struct Place: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String? }
        let results: [Place]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let cloud_cover: Int
            let weather_code: Int
        }
        struct Daily: Decodable { let sunshine_duration: [Double] }
        struct Hourly: Decodable {
            let time: [String]
            let shortwave_radiation: [Double]
            let temperature_2m: [Double]
        }
        let current: Current
        let daily: Daily
        let hourly: Hourly
    }

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func locate(_ location: String) async throws -> WeatherLocation {
        let place = try await geocode(location)
        return WeatherLocation(
            name: [place.name, place.admin1].compactMap { $0 }.joined(separator: ", "),
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    func fetch(location: String, panelPowerWp: Double, samples: [SizingHistoryStore.Sample]) async throws -> WeatherReport {
        let place = try await geocode(location)
        
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,cloud_cover,weather_code"),
            .init(name: "hourly", value: "shortwave_radiation,temperature_2m"),
            .init(name: "daily", value: "sunshine_duration"),
            .init(name: "past_days", value: "7"),
            .init(name: "forecast_days", value: "3"),
            .init(name: "timezone", value: "auto")
        ]
        let value: ForecastResponse = try await request(forecast.url!)
        let weather = WeatherSnapshot(
            locationName: [place.name, place.admin1].compactMap { $0 }.joined(separator: ", "),
            temperatureCelsius: value.current.temperature_2m,
            cloudCoverPercent: value.current.cloud_cover,
            weatherCode: value.current.weather_code,
            sunshineDurationSeconds: value.daily.sunshine_duration.first ?? 0,
            updatedAt: .now
        )
        return WeatherReport(
            weather: weather,
            solarForecast: makeSolarForecast(response: value, panelPowerWp: panelPowerWp, samples: samples)
        )
    }

    private func geocode(_ location: String) async throws -> GeocodingResponse.Place {
        let query = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { throw SolarFlowServiceError.invalidConfiguration("Renseignez une ville dans Configuration → Météo locale.") }
        var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geo.queryItems = [
            .init(name: "name", value: query), .init(name: "count", value: "1"),
            .init(name: "language", value: "fr"), .init(name: "format", value: "json")
        ]
        let geocoding: GeocodingResponse = try await request(geo.url!)
        guard let place = geocoding.results?.first else {
            throw SolarFlowServiceError.invalidConfiguration("Ville météo introuvable.")
        }
        return place
    }

    private func makeSolarForecast(
        response: ForecastResponse,
        panelPowerWp: Double,
        samples: [SizingHistoryStore.Sample]
    ) -> SolarProductionForecast? {
        guard panelPowerWp > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        guard response.hourly.time.count == response.hourly.shortwave_radiation.count else { return nil }

        var radiation: [Date: Double] = [:]
        for (time, irradiance) in zip(response.hourly.time, response.hourly.shortwave_radiation) {
            guard let date = formatter.date(from: time),
                  let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start else { continue }
            radiation[hour] = irradiance
        }
        let ratios = samples.compactMap { sample -> Double? in
            let hour = Calendar.current.dateInterval(of: .hour, for: sample.date)!.start
            guard let irradiance = radiation[hour], irradiance >= 100, sample.solarWatts >= 20 else { return nil }
            return Double(sample.solarWatts) / (panelPowerWp * irradiance / 1_000)
        }.sorted()
        let learned = ratios.isEmpty ? 0.78 : ratios[ratios.count / 2]
        let factor = min(1.15, max(0.35, learned))
        let today = Calendar.current.startOfDay(for: .now)
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return nil }
        var points: [SolarProductionForecast.Point] = []
        for (hour, irradiance) in radiation where hour >= today && hour < tomorrow {
            let watts = min(panelPowerWp, max(0, panelPowerWp * irradiance / 1_000 * factor))
            points.append(.init(date: hour, watts: watts))
        }
        points.sort { $0.date < $1.date }
        guard !points.isEmpty else { return nil }
        let days = Set(samples.filter { $0.solarWatts >= 20 }.map { Calendar.current.startOfDay(for: $0.date) }).count
        return SolarProductionForecast(
            points: points,
            totalKWh: points.reduce(0) { $0 + $1.watts / 1_000 },
            remainingKWh: points.filter { $0.date >= Date() }.reduce(0) { $0 + $1.watts / 1_000 },
            calibrationFactor: factor,
            calibrationDays: days
        )
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SolarFlowServiceError.unexpectedResponse
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

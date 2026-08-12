import Foundation

struct WeatherSnapshot: Equatable, Sendable {
    let locationName: String
    let temperatureCelsius: Double
    let cloudCoverPercent: Int
    let weatherCode: Int
    let sunshineDurationSeconds: Double
    let updatedAt: Date

    var cloudFactor: Double { max(0, min(1, 1 - Double(cloudCoverPercent) / 100)) }
}

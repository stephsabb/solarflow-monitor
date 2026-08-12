import Foundation

struct SolarProductionForecast: Equatable, Sendable {
    struct Point: Identifiable, Equatable, Sendable {
        let date: Date
        let watts: Double
        var id: Date { date }
    }

    let points: [Point]
    let totalKWh: Double
    let remainingKWh: Double
    let calibrationFactor: Double
    let calibrationDays: Int

    var confidenceLabel: String {
        switch calibrationDays {
        case 7...: "Bonne"
        case 3...: "Moyenne"
        default: "Initiale"
        }
    }
}

struct WeatherReport: Sendable {
    let weather: WeatherSnapshot
    let solarForecast: SolarProductionForecast?
}

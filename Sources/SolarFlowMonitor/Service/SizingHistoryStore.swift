import Foundation

enum SizingHistoryStore {
    struct Sample: Codable, Sendable, Identifiable {
        let date: Date
        let solarWatts: Int
        let homeWatts: Int
        let socPercent: Int
        let gridWatts: Int?

        var id: Date { date }
        var totalHomeWatts: Int { max(0, homeWatts + (gridWatts ?? 0)) }
    }

    struct Indicators: Sendable {
        let coverageDays: Int
        let sampledHours: Double
        let fullWithSolarHours: Double
        let minimumWithImportHours: Double
        let fullDays: Int
        let minimumEveningDays: Int
    }

    private static let key = "sizingHistorySamples-v1"

    static func record(snapshot: SolarFlowSnapshot, gridPowerWatts: Int?) {
        var samples = load()
        if let last = samples.last, snapshot.updatedAt.timeIntervalSince(last.date) < 45 { return }
        samples.append(Sample(
            date: snapshot.updatedAt,
            solarWatts: snapshot.solarPowerWatts,
            homeWatts: snapshot.homePowerWatts,
            socPercent: snapshot.batteryLevelPercent,
            gridWatts: gridPowerWatts
        ))
        let cutoff = Calendar.current.date(byAdding: .day, value: -35, to: .now) ?? .distantPast
        samples.removeAll { $0.date < cutoff }
        if let data = try? JSONEncoder().encode(samples) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func indicators(minimumSOC: Int) -> Indicators {
        let samples = load().filter { $0.date >= (Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast) }
        let calendar = Calendar.current
        let days = Set(samples.map { calendar.startOfDay(for: $0.date) })
        let full = samples.filter { $0.socPercent >= 99 && $0.solarWatts >= 100 }
        let minimum = samples.filter { $0.socPercent <= minimumSOC && ($0.gridWatts ?? 0) >= 100 }
        let eveningMinimum = samples.filter {
            let hour = calendar.component(.hour, from: $0.date)
            return hour >= 18 && $0.socPercent <= minimumSOC && ($0.gridWatts ?? 0) >= 100
        }
        return Indicators(
            coverageDays: days.count,
            sampledHours: Double(samples.count) / 60,
            fullWithSolarHours: Double(full.count) / 60,
            minimumWithImportHours: Double(minimum.count) / 60,
            fullDays: Set(full.map { calendar.startOfDay(for: $0.date) }).count,
            minimumEveningDays: Set(eveningMinimum.map { calendar.startOfDay(for: $0.date) }).count
        )
    }

    static func recentSamples(hours: Int = 24) -> [Sample] {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: .now) ?? .distantPast
        return load().filter { $0.date >= cutoff }
    }

    static func calibrationSamples(days: Int = 7) -> [Sample] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return load().filter { $0.date >= cutoff }
    }

    private static func load() -> [Sample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([Sample].self, from: data) else { return [] }
        return values.sorted { $0.date < $1.date }
    }
}

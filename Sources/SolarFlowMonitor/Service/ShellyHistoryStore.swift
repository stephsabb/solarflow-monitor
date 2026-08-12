import Foundation

enum ShellyHistoryStore {
    private struct Counter: Codable {
        let timestamp: Date
        let importedWh: Double
        let exportedWh: Double
    }

    struct Energy: Sendable {
        let importedKWh: Double
        let exportedKWh: Double
    }

    private static let key = "shellyEnergyCounters"

    static func record(_ snapshot: ShellyMeterSnapshot) {
        var values = load()
        if let last = values.last,
           last.importedWh == snapshot.importedEnergyWh,
           last.exportedWh == snapshot.exportedEnergyWh { return }
        values.append(Counter(timestamp: snapshot.updatedAt, importedWh: snapshot.importedEnergyWh, exportedWh: snapshot.exportedEnergyWh))
        let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: .now) ?? .distantPast
        values.removeAll { $0.timestamp < cutoff }
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func energy(from begin: Date, to end: Date) -> Energy? {
        let calendar = Calendar.current
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let all = load()
        guard let before = all.last(where: { $0.timestamp <= begin }) ?? all.first(where: { $0.timestamp >= begin }),
              let after = all.last(where: { $0.timestamp < endExclusive }),
              after.timestamp > before.timestamp else { return nil }
        return Energy(
            importedKWh: max(0, after.importedWh - before.importedWh) / 1_000,
            exportedKWh: max(0, after.exportedWh - before.exportedWh) / 1_000
        )
    }

    private static func load() -> [Counter] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([Counter].self, from: data) else { return [] }
        return values.sorted { $0.timestamp < $1.timestamp }
    }
}

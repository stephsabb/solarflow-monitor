import Foundation

struct EnergyHistoryDay: Identifiable, Equatable, Sendable {
    let date: Date
    let solar: Double
    let home: Double
    let batteryInput: Double
    let batteryOutput: Double
    let gridImport: Double?
    let gridExport: Double?

    var totalHome: Double? {
        guard let gridImport, let gridExport else { return nil }
        return max(0, home + gridImport - gridExport)
    }

    var id: Date { date }
}

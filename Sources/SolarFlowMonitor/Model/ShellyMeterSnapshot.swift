import Foundation

struct ShellyMeterSnapshot: Equatable, Sendable {
    /// Positive means import from grid, negative means export to grid.
    let gridPowerWatts: Int
    let importedEnergyWh: Double
    let exportedEnergyWh: Double
    let updatedAt: Date
}

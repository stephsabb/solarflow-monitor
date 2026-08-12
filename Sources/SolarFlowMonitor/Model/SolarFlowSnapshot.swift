import Foundation

struct SolarFlowSnapshot: Codable, Equatable, Sendable {
    enum ConnectionState: String, Codable, Sendable {
        case connected
        case disconnected
    }

    let solarPowerWatts: Int
    let homePowerWatts: Int
    let batteryLevelPercent: Int
    /// Positive means charging; negative means discharging.
    let batteryPowerWatts: Int
    let connectionState: ConnectionState
    let updatedAt: Date
}

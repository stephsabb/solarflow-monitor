import Foundation
import Testing
@testable import SolarFlowMonitor

@Test func snapshotDecodesNormalizedCloudPayload() throws {
    let json = #"{"solarPowerWatts":1240,"homePowerWatts":620,"batteryLevelPercent":78,"batteryPowerWatts":620,"connectionState":"connected","updatedAt":"2026-08-08T10:42:00Z"}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(SolarFlowSnapshot.self, from: Data(json.utf8))
    #expect(snapshot.solarPowerWatts == 1240)
    #expect(snapshot.batteryPowerWatts == 620)
    #expect(snapshot.connectionState == .connected)
}

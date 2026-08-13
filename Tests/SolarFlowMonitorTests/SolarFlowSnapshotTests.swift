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

@Test func detectsEverySolarFlow800NamingVariant() {
    #expect(ZendureSolarFlow.matches("SolarFlow 800"))
    #expect(ZendureSolarFlow.matches("SolarFlow-800 Pro"))
    #expect(ZendureSolarFlow.matches("SolarFlow 800 Pro 2"))
    #expect(ZendureSolarFlow.matches("SolarFlow800Pro2"))
    #expect(ZendureSolarFlow.matches("SolarFlow 800 Plus"))
    #expect(ZendureSolarFlow.matches("SF800 Plus"))
    #expect(ZendureSolarFlow.matches("SolarFlow 1600 AC+"))
    #expect(ZendureSolarFlow.matches("SolarFlow 2400 AC"))
    #expect(ZendureSolarFlow.matches("SolarFlow 2400 Pro"))
    #expect(ZendureSolarFlow.matches("SolarFlow 3000 Mix AC+"))
    #expect(ZendureSolarFlow.matches("SolarFlow 4000 AC+"))
    #expect(ZendureSolarFlow.matches("Hyper 2000"))
    #expect(ZendureSolarFlow.matches("Hub 1200"))
    #expect(ZendureSolarFlow.matches("Hub2000"))
    #expect(ZendureSolarFlow.matches("AIO 2400"))
    #expect(!ZendureSolarFlow.matches("ACE 1500"))
    #expect(!ZendureSolarFlow.matches("AB2000S"))
    #expect(!ZendureSolarFlow.matches("SmartMeter 3CT"))
}

@Test func aggregatesAllControllersWithoutCountingPacksSeparately() {
    let snapshot = ZendureSolarFlow.aggregate([
        ["solarInputPower": 720, "outputHomePower": 350, "outputPackPower": 370, "packInputPower": 0, "electricLevel": 60],
        ["solarInputPower": 580, "outputHomePower": 280, "outputPackPower": 0, "packInputPower": 190, "electricLevel": 80]
    ], updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

    #expect(snapshot.solarPowerWatts == 1_300)
    #expect(snapshot.homePowerWatts == 630)
    #expect(snapshot.batteryPowerWatts == 180)
    #expect(snapshot.batteryLevelPercent == 70)
}

@Test func normalizesPowerAliasesUsedByACAndHyperModels() {
    let values = ZendureSolarFlow.canonicalValues(properties: [
        "solarOutputPower": "1480.0",
        "acOutputPower": 630,
        "globalSoc": ["value": 74],
        "packChargePower": 850
    ], data: [:])
    #expect(values["solarInputPower"] == 1_480)
    #expect(values["outputHomePower"] == 630)
    #expect(values["electricLevel"] == 74)
    #expect(values["outputPackPower"] == 850)
}

@Test func sumsIndividualPVInputsAndPackDataFallback() {
    let values = ZendureSolarFlow.canonicalValues(properties: [
        "solarPower1": 420, "solarPower2": 390, "solarPower3": 210
    ], data: ["packData": [
        ["state": 1, "power": -300], ["state": 1, "power": 200], ["state": 2, "power": 125]
    ]])
    #expect(values["solarInputPower"] == 1_020)
    #expect(values["outputPackPower"] == 500)
    #expect(values["packInputPower"] == 125)
}

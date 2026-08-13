import Foundation

enum ZendureSolarFlow {
    /// Controllers whose measurements can be safely aggregated once. Satellite
    /// batteries and paired ACE units are intentionally excluded to avoid
    /// counting power already reported by their parent controller twice.
    static func matches(_ labels: String?...) -> Bool {
        let normalized = labels.compactMap { $0 }.map(normalize).joined()
        let solarFlowFamilies = [
            "solarflow800", "sf800",
            "solarflow1600", "sf1600",
            "solarflow2400", "sf2400",
            "solarflow3000", "sf3000",
            "solarflow4000", "sf4000"
        ]
        return solarFlowFamilies.contains(where: normalized.contains)
            || normalized.contains("hyper2000")
            || normalized.contains("hub1200")
            || normalized.contains("hub2000")
            || normalized.contains("aio2400")
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
            .lowercased()
    }

    static func aggregate(_ values: [[String: Int]], updatedAt: Date) -> SolarFlowSnapshot {
        let solar = values.reduce(0) { $0 + $1["solarInputPower", default: 0] }
        let home = values.reduce(0) { $0 + $1["outputHomePower", default: 0] }
        let charge = values.reduce(0) { $0 + $1["outputPackPower", default: 0] }
        let discharge = values.reduce(0) { $0 + $1["packInputPower", default: 0] }
        let levels = values.compactMap { $0["electricLevel"] }
        let level = levels.isEmpty ? 0 : levels.reduce(0, +) / levels.count
        return SolarFlowSnapshot(
            solarPowerWatts: solar,
            homePowerWatts: home,
            batteryLevelPercent: level,
            batteryPowerWatts: charge - discharge,
            connectionState: .connected,
            updatedAt: updatedAt
        )
    }

    static func canonicalValues(properties: [String: Any], data: [String: Any]) -> [String: Int] {
        let aliases: [String: [String]] = [
            "solarInputPower": ["solarInputPower", "pvPower", "solarPower", "solarOutputPower", "inputPower"],
            "outputHomePower": ["outputHomePower", "homePower", "homeLoad", "acOutputPower", "outputPower"],
            "electricLevel": ["electricLevel", "soc", "socLevel", "globalSoc"],
            "outputPackPower": ["outputPackPower", "batteryChargePower", "packChargePower"],
            "packInputPower": ["packInputPower", "batteryDischargePower", "packDischargePower"]
        ]
        var result: [String: Int] = [:]
        for (canonical, names) in aliases {
            for name in names {
                if let value = integer(properties[name]) {
                    result[canonical] = value
                    break
                }
            }
        }
        if result["solarInputPower"] == nil {
            let inputs = (1...8).compactMap { integer(properties["solarPower\($0)"]) }
            if !inputs.isEmpty { result["solarInputPower"] = inputs.reduce(0, +) }
        }
        if let packs = data["packData"] as? [[String: Any]], !packs.isEmpty {
            var charge = 0, discharge = 0
            for pack in packs {
                let power = integer(pack["power"]) ?? 0
                switch integer(pack["state"]) {
                case 1: charge += abs(power)
                case 2: discharge += abs(power)
                default: break
                }
            }
            if result["outputPackPower"] == nil { result["outputPackPower"] = charge }
            if result["packInputPower"] == nil { result["packInputPower"] = discharge }
        }
        return result
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(Double(string) ?? .nan) }
        if let wrapped = value as? [String: Any] { return integer(wrapped["value"]) }
        return nil
    }
}

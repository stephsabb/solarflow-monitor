import Foundation

actor ShellyCloudService {
    private let server: String
    private let deviceID: String
    private let authKey: String

    init(server: String, deviceID: String, authKey: String) {
        self.server = server.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authKey = authKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchSnapshot() async throws -> ShellyMeterSnapshot {
        guard !server.isEmpty, !deviceID.isEmpty, !authKey.isEmpty else {
            throw SolarFlowServiceError.invalidConfiguration("Configuration Shelly Cloud incomplète.")
        }
        for candidate in deviceIDCandidates {
            if let result = try? await fetchSnapshot(deviceID: candidate) { return result }
        }
        throw SolarFlowServiceError.invalidConfiguration("Aucune mesure Shelly 3EM trouvée. Vérifiez le Device Id à 12 caractères.")
    }

    func fetchHistory(period: ZendureHistoryService.Period) async throws -> [Date: ShellyHistoryStore.Energy] {
        guard !server.isEmpty, !deviceID.isEmpty, !authKey.isEmpty else {
            throw SolarFlowServiceError.invalidConfiguration("Configuration Shelly Cloud incomplète.")
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let begin: Date
        switch period {
        case .sevenDays: begin = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .thirtyDays: begin = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .month: begin = calendar.dateInterval(of: .month, for: today)?.start ?? today
        case .year: begin = calendar.dateInterval(of: .year, for: today)?.start ?? today
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for candidate in deviceIDCandidates.reversed() {
            guard var components = URLComponents(url: try cloudBaseURL().appending(path: "v2/statistics/power-consumption/em-3p"), resolvingAgainstBaseURL: false) else { continue }
            components.queryItems = [
                URLQueryItem(name: "id", value: candidate),
                URLQueryItem(name: "channel", value: "0"),
                URLQueryItem(name: "date_range", value: "custom"),
                URLQueryItem(name: "date_from", value: formatter.string(from: begin)),
                URLQueryItem(name: "date_to", value: formatter.string(from: .now)),
                URLQueryItem(name: "period", value: "5"),
                URLQueryItem(name: "auth_key", value: authKey)
            ]
            guard let url = components.url else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            let rows = historyRows(in: json)
            if !rows.isEmpty { return aggregateHistory(rows, period: period, calendar: calendar) }
        }
        throw SolarFlowServiceError.invalidConfiguration("Shelly Cloud n’a renvoyé aucune statistique pour cette période.")
    }

    private func cloudBaseURL() throws -> URL {
        let normalizedServer = server.hasPrefix("http") ? server : "https://\(server)"
        guard let serverURL = URL(string: normalizedServer),
              var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            throw SolarFlowServiceError.invalidConfiguration("Adresse du serveur Shelly invalide.")
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw SolarFlowServiceError.invalidConfiguration("Adresse du serveur Shelly invalide.") }
        return url
    }

    private func fetchSnapshot(deviceID requestedDeviceID: String) async throws -> ShellyMeterSnapshot {
        let normalizedServer = server.hasPrefix("http") ? server : "https://\(server)"
        guard let serverURL = URL(string: normalizedServer),
              var baseComponents = URLComponents(url: serverURL, resolvingAgainstBaseURL: false) else {
            throw SolarFlowServiceError.invalidConfiguration("Adresse du serveur Shelly invalide.")
        }
        // The value copied from Shelly can include a device WebSocket path. Cloud Control
        // endpoints always live at the root of the same host.
        baseComponents.path = ""
        baseComponents.query = nil
        baseComponents.fragment = nil
        guard let baseURL = baseComponents.url,
              var components = URLComponents(url: baseURL.appending(path: "v2/devices/api/get"), resolvingAgainstBaseURL: false) else {
            throw SolarFlowServiceError.invalidConfiguration("Adresse du serveur Shelly invalide.")
        }
        components.queryItems = [URLQueryItem(name: "auth_key", value: authKey)]
        guard let url = components.url else { throw SolarFlowServiceError.unexpectedResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "ids": [requestedDeviceID],
            "select": ["status"],
            "pick": ["status": ["em:0", "emdata:0", "em1:0", "em1:1", "em1:2", "em1data:0", "em1data:1", "em1data:2"]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw SolarFlowServiceError.invalidConfiguration("Shelly Cloud a refusé la requête ou n’a pas trouvé le compteur.")
        }
        if let status = statusObject(in: json), let snapshot = meterSnapshot(in: status) { return snapshot }

        // Some Shelly tenants omit component data from the v2 response. The legacy
        // status endpoint still returns the complete Gen2 Shelly.GetStatus payload.
        if let legacy = try await fetchLegacyStatus(baseURL: baseURL, deviceID: requestedDeviceID),
           let snapshot = meterSnapshot(in: legacy) {
            return snapshot
        }
        throw SolarFlowServiceError.invalidConfiguration("Le statut Shelly ne contient pas les mesures du Pro 3EM.")
    }

    private var deviceIDCandidates: [String] {
        var candidates = [deviceID]
        let compact = deviceID.lowercased().filter { $0.isHexDigit }
        if compact.count >= 12 {
            let mac = String(compact.suffix(12))
            if !candidates.contains(mac) { candidates.append(mac) }
        }
        if let suffix = deviceID.split(separator: "-").last {
            let value = suffix.lowercased()
            if value.count == 12, value.allSatisfy(\.isHexDigit), !candidates.contains(value) { candidates.append(value) }
        }
        return candidates
    }

    private func meterSnapshot(in status: [String: Any]) -> ShellyMeterSnapshot? {
        // Shelly 3EM Gen1 (SHEM-3) exposes one `emeters` item per phase.
        if let emeters = findArray(named: "emeters", in: status) as? [[String: Any]], !emeters.isEmpty {
            return snapshot(
                power: emeters.reduce(0) { $0 + number($1["power"]) },
                imported: emeters.reduce(0) { $0 + number($1["total"]) },
                exported: emeters.reduce(0) { $0 + number($1["total_returned"]) }
            )
        }

        if let em = findDictionary(named: "em:0", in: status),
           let emData = findDictionary(named: "emdata:0", in: status) {
            let power = number(em["total_act_power"] ?? em["total_active_power"])
            let phasePower = ["a_act_power", "b_act_power", "c_act_power"].reduce(0.0) { $0 + number(em[$1]) }
            let imported = number(emData["total_act"])
            let exported = number(emData["total_act_ret"])
            let phaseImported = ["a_total_act_energy", "b_total_act_energy", "c_total_act_energy"].reduce(0.0) { $0 + number(emData[$1]) }
            let phaseExported = ["a_total_act_ret_energy", "b_total_act_ret_energy", "c_total_act_ret_energy"].reduce(0.0) { $0 + number(emData[$1]) }
            return snapshot(power: power == 0 ? phasePower : power,
                            imported: imported == 0 ? phaseImported : imported,
                            exported: exported == 0 ? phaseExported : exported)
        }

        // Pro 3EM can also be configured in monophase profile (EM1 components).
        let meters = (0...2).compactMap { findDictionary(named: "em1:\($0)", in: status) }
        let counters = (0...2).compactMap { findDictionary(named: "em1data:\($0)", in: status) }
        guard !meters.isEmpty, !counters.isEmpty else { return nil }
        return snapshot(
            power: meters.reduce(0) { $0 + number($1["act_power"]) },
            imported: counters.reduce(0) { $0 + number($1["total_act_energy"]) },
            exported: counters.reduce(0) { $0 + number($1["total_act_ret_energy"]) }
        )
    }

    private func snapshot(power: Double, imported: Double, exported: Double) -> ShellyMeterSnapshot {
        ShellyMeterSnapshot(
            gridPowerWatts: Int(power.rounded()),
            importedEnergyWh: imported,
            exportedEnergyWh: exported,
            updatedAt: .now
        )
    }

    private func fetchLegacyStatus(baseURL: URL, deviceID: String) async throws -> [String: Any]? {
        var request = URLRequest(url: baseURL.appending(path: "device/status"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "id", value: deviceID), URLQueryItem(name: "auth_key", value: authKey)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return statusObject(in: json)
    }

    private func statusObject(in value: Any) -> [String: Any]? {
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            return statusObject(in: decoded)
        }
        if let array = value as? [Any] { return array.compactMap { statusObject(in: $0) }.first }
        guard let object = value as? [String: Any] else { return nil }
        if object["emeters"] is [Any] || object.keys.contains(where: { $0.hasPrefix("em:") || $0.hasPrefix("em1:") }) { return object }
        for child in object.values {
            if let found = statusObject(in: child) { return found }
        }
        return nil
    }

    private func findDictionary(named name: String, in value: Any) -> [String: Any]? {
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            return findDictionary(named: name, in: decoded)
        }
        if let object = value as? [String: Any] {
            if let found = object[name] as? [String: Any] { return found }
            for child in object.values {
                if let found = findDictionary(named: name, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findDictionary(named: name, in: child) { return found }
            }
        }
        return nil
    }

    private func findArray(named name: String, in value: Any) -> [Any]? {
        if let object = value as? [String: Any] {
            if let found = object[name] as? [Any] { return found }
            for child in object.values {
                if let found = findArray(named: name, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findArray(named: name, in: child) { return found }
            }
        }
        return nil
    }

    private func number(_ value: Any?) -> Double {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    private func historyRows(in value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            if object["datetime"] != nil, object["consumption"] != nil || object["active_net"] != nil { return [object] }
            if let sum = object["sum"] as? [[String: Any]], !sum.isEmpty { return sum }
            return object.values.flatMap { historyRows(in: $0) }
        }
        if let array = value as? [Any] { return array.flatMap { historyRows(in: $0) } }
        return []
    }

    private func aggregateHistory(
        _ rows: [[String: Any]],
        period: ZendureHistoryService.Period,
        calendar: Calendar
    ) -> [Date: ShellyHistoryStore.Energy] {
        var totals: [Date: (imported: Double, exported: Double)] = [:]
        for row in rows {
            guard let rawDate = row["datetime"] as? String, let date = parseHistoryDate(rawDate) else { continue }
            let key: Date
            if period == .year {
                key = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
            } else {
                key = calendar.startOfDay(for: date)
            }
            var value = totals[key] ?? (0, 0)
            value.imported += number(row["consumption"] ?? row["active_net"])
            value.exported += number(row["reversed"])
            totals[key] = value
        }
        return totals.mapValues { ShellyHistoryStore.Energy(importedKWh: $0.imported / 1_000, exportedKWh: $0.exported / 1_000) }
    }

    private func parseHistoryDate(_ value: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

import Foundation

actor ZendureHistoryService {
    enum Period: String, CaseIterable, Identifiable, Sendable {
        case sevenDays = "7 jours"
        case thirtyDays = "30 jours"
        case month = "Mois"
        case year = "Année"
        var id: Self { self }
    }

    private struct Session: Sendable {
        let token: String
        let baseURL: URL
        let zone: String
    }

    private let email: String
    private let password: String
    private let urlSession: URLSession

    init(email: String, password: String, urlSession: URLSession = .shared) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
        self.urlSession = urlSession
    }

    func fetch(period: Period) async throws -> [EnergyHistoryDay] {
        guard !email.isEmpty, !password.isEmpty else {
            throw SolarFlowServiceError.invalidConfiguration("Renseignez l’e-mail et le mot de passe Zendure pour l’historique.")
        }
        let session = try await authenticate()
        let deviceIDs = try await fetchSolarFlowDeviceIDs(session: session)
        guard !deviceIDs.isEmpty else {
            throw SolarFlowServiceError.invalidConfiguration("Aucun SolarFlow 800 Pro / Plus trouvé pour l’historique.")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.zone) ?? .current
        let today = calendar.startOfDay(for: .now)
        let buckets = historyBuckets(period: period, today: today, calendar: calendar)
        var result: [EnergyHistoryDay] = []
        for bucket in buckets {
            var total = EnergyValues()
            for id in deviceIDs {
                total += try await fetchEnergy(
                    deviceID: id,
                    beginDate: bucket.begin,
                    endDate: bucket.end,
                    requestType: bucket.requestType,
                    calendar: calendar,
                    session: session
                )
            }
            result.append(EnergyHistoryDay(
                date: bucket.begin,
                solar: total.solar,
                home: total.home,
                batteryInput: total.batteryInput,
                batteryOutput: total.batteryOutput,
                gridImport: nil,
                gridExport: nil
            ))
        }
        return result
    }

    private func historyBuckets(period: Period, today: Date, calendar: Calendar) -> [(begin: Date, end: Date, requestType: Int)] {
        switch period {
        case .sevenDays:
            return stride(from: 6, through: 0, by: -1).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, $0, 0) }
            }
        case .thirtyDays:
            return stride(from: 29, through: 0, by: -1).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).map { ($0, $0, 0) }
            }
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: today) else { return [] }
            let dayCount = calendar.dateComponents([.day], from: interval.start, to: today).day ?? 0
            return (0...dayCount).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: interval.start).map { ($0, $0, 0) }
            }
        case .year:
            guard let year = calendar.dateInterval(of: .year, for: today) else { return [] }
            let currentMonth = calendar.component(.month, from: today)
            return (0..<currentMonth).compactMap { offset in
                guard let begin = calendar.date(byAdding: .month, value: offset, to: year.start),
                      let next = calendar.date(byAdding: .month, value: 1, to: begin),
                      let monthEnd = calendar.date(byAdding: .day, value: -1, to: next) else { return nil }
                return (begin, min(monthEnd, today), 2)
            }
        }
    }

    private func authenticate() async throws -> Session {
        let url = URL(string: "https://app.zendure.tech/eu/auth/app/token")!
        let credentials = Data("\(email):\(password)".utf8).base64EncodedString()
        let body: [String: Any] = [
            "account": email, "password": password,
            "appId": "121c83f761305d6cf7b", "appType": "iOS",
            "grantType": "password", "tenantId": ""
        ]
        let object = try await post(url: url, body: body, headers: ["Authorization": "Basic \(credentials)"])
        guard let data = object["data"] as? [String: Any],
              let token = string(data["accessToken"]),
              let base = string(data["serverNodeUrl"]), let baseURL = URL(string: base) else {
            throw apiError(object, fallback: "Identifiants Zendure refusés ou réponse d’authentification inconnue.")
        }
        return Session(token: token, baseURL: baseURL, zone: string(data["zone"]) ?? TimeZone.current.identifier)
    }

    private func fetchSolarFlowDeviceIDs(session: Session) async throws -> [String] {
        let url = session.baseURL.appending(path: "productModule/device/queryDeviceListByConsumerId")
        let object = try await post(url: url, body: [:], headers: authorizedHeaders(session, consumerApp: true))
        guard let devices = object["data"] as? [[String: Any]] else {
            throw apiError(object, fallback: "La liste des appareils Zendure est illisible.")
        }
        return devices.compactMap { device in
            guard ZendureSolarFlow.matches(
                string(device["productName"]), string(device["name"]), string(device["productModel"])
            ) else { return nil }
            return string(device["id"])
        }
    }

    private func fetchEnergy(
        deviceID: String,
        beginDate: Date,
        endDate: Date,
        requestType: Int,
        calendar: Calendar,
        session: Session
    ) async throws -> EnergyValues {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let begin = formatter.string(from: beginDate)
        let end = formatter.string(from: endDate)
        let body: [String: Any] = [
            "aceId": "", "deviceId": deviceID, "beginDate": begin,
            "endDate": end, "zone": session.zone, "type": requestType
        ]
        let url = session.baseURL.appending(path: "tdengine/device/solarFlow/energy")
        let object = try await post(url: url, body: body, headers: authorizedHeaders(session))
        guard let data = object["data"] as? [String: Any] else {
            throw apiError(object, fallback: "L’historique Zendure est illisible pour la période demandée.")
        }
        return EnergyValues(
            solar: kilowattHours(data["solar"]), home: kilowattHours(data["home"]),
            batteryInput: kilowattHours(data["batteryInput"]), batteryOutput: kilowattHours(data["batteryOutput"])
        )
    }

    private func authorizedHeaders(_ session: Session, consumerApp: Bool = false) -> [String: String] {
        var headers = ["Blade-Auth": "bearer \(session.token)"]
        if consumerApp { headers["Authorization"] = "Basic Q29uc3VtZXJBcHA6NX4qUmRuTnJATWg0WjEyMw==" }
        return headers
    }

    private func post(url: URL, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("fr-FR", forHTTPHeaderField: "Accept-Language")
        request.setValue("4.3.1", forHTTPHeaderField: "appVersion")
        request.setValue("Zendure/4.3.1 (iPhone; iOS 18.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolarFlowServiceError.unexpectedResponse
        }
        if let code = (object["code"] as? NSNumber)?.intValue, code == 400 || code == 401 {
            throw apiError(object, fallback: "Accès Zendure refusé.")
        }
        return object
    }

    private func apiError(_ object: [String: Any], fallback: String) -> SolarFlowServiceError {
        .invalidConfiguration(string(object["msg"]) ?? fallback)
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func number(_ value: Any?) -> Double {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) ?? 0 }
        return 0
    }

    /// The private Zendure endpoint returns accumulated energy in Wh.
    private func kilowattHours(_ value: Any?) -> Double {
        number(value) / 1_000
    }

}

private struct EnergyValues {
    var solar = 0.0
    var home = 0.0
    var batteryInput = 0.0
    var batteryOutput = 0.0

    static func += (left: inout Self, right: Self) {
        left.solar += right.solar
        left.home += right.home
        left.batteryInput += right.batteryInput
        left.batteryOutput += right.batteryOutput
    }
}

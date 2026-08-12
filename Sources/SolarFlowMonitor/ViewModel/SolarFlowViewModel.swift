import Foundation

@MainActor
final class SolarFlowViewModel: ObservableObject {
    @Published private(set) var snapshot: SolarFlowSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var history: [EnergyHistoryDay] = []
    @Published private(set) var historyError: String?
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var shellyError: String?
    @Published private(set) var isShellyConnected = false
    @Published var showSizingAnalysis = false
    @Published private(set) var sizingHistory: [EnergyHistoryDay] = []
    @Published private(set) var sizingError: String?
    @Published private(set) var isLoadingSizing = false
    @Published private(set) var recentSamples: [SizingHistoryStore.Sample] = SizingHistoryStore.recentSamples()
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var weatherError: String?
    @Published private(set) var solarForecast: SolarProductionForecast?
    @Published var configuration: CloudConfiguration {
        didSet {
            if !isApplyingKeychainSecrets { Self.save(configuration) }
        }
    }

    private var refreshTask: Task<Void, Never>?
    private var cloudService: ZendureCloudService?
    private var activeCloudKey = ""
    private var lastWeatherRefresh = Date.distantPast
    private let weatherService = OpenMeteoService()
    private var secretsWereLoaded = false
    private var isApplyingKeychainSecrets = false

    var isShellyConfigured: Bool {
        !configuration.shellyServer.isEmpty && !configuration.shellyDeviceID.isEmpty && !configuration.shellyAuthKey.isEmpty
    }

    var hasShellyHistory: Bool { history.contains { $0.gridImport != nil && $0.gridExport != nil } }

    init() {
        self.configuration = SolarFlowViewModel.load()
    }

    init(configuration: CloudConfiguration) {
        self.configuration = configuration
    }

    deinit { refreshTask?.cancel() }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            await self?.unlockSecretsIfNeeded()
            while !Task.isCancelled {
                await self?.refresh()
                await self?.refreshWeatherIfNeeded()
                // Task.sleep is suspended with the process while macOS sleeps;
                // no refresh requests are accumulated during standby.
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func unlockSecretsIfNeeded() async {
        guard !secretsWereLoaded else { return }
        // Let the menu-bar application finish presenting before Keychain asks
        // for Touch ID / user presence.
        try? await Task.sleep(for: .milliseconds(350))
        guard let secrets = KeychainStore.loadSecrets(
            legacyCloudKey: Self.defaults.string(forKey: "cloudKey") ?? ""
        ) else { return }
        secretsWereLoaded = true
        isApplyingKeychainSecrets = true
        configuration.cloudKey = secrets.cloudKey
        configuration.zendurePassword = secrets.zendurePassword
        configuration.shellyAuthKey = secrets.shellyAuthKey
        isApplyingKeychainSecrets = false
        if Self.defaults.bool(forKey: "protectSecretsWithTouchID") {
            KeychainStore.saveSecrets(secrets, recreateAccessControl: true)
            Self.defaults.removeObject(forKey: "protectSecretsWithTouchID")
        }
        Self.defaults.removeObject(forKey: "cloudKey")
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func restart() {
        stop()
        snapshot = nil
        errorMessage = nil
        lastWeatherRefresh = .distantPast
        start()
    }

    private func refreshWeatherIfNeeded() async {
        guard Date().timeIntervalSince(lastWeatherRefresh) >= 30 * 60 else { return }
        lastWeatherRefresh = .now
        do {
            let report = try await weatherService.fetch(
                location: configuration.weatherLocation,
                panelPowerWp: configuration.panelPowerWp,
                samples: SizingHistoryStore.calibrationSamples()
            )
            weather = report.weather
            solarForecast = report.solarForecast
            weatherError = nil
        } catch {
            weatherError = error.localizedDescription
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let freshSnapshot = try await makeService().fetchSnapshot()
            if isShellyConfigured {
                do {
                    let meter = try await makeShellyService().fetchSnapshot()
                    ShellyHistoryStore.record(meter)
                    SizingHistoryStore.record(snapshot: freshSnapshot, gridPowerWatts: meter.gridPowerWatts)
                    recentSamples = SizingHistoryStore.recentSamples()
                    snapshot = SolarFlowSnapshot(
                        solarPowerWatts: freshSnapshot.solarPowerWatts,
                        homePowerWatts: max(0, freshSnapshot.homePowerWatts + meter.gridPowerWatts),
                        batteryLevelPercent: freshSnapshot.batteryLevelPercent,
                        batteryPowerWatts: freshSnapshot.batteryPowerWatts,
                        connectionState: freshSnapshot.connectionState,
                        updatedAt: max(freshSnapshot.updatedAt, meter.updatedAt)
                    )
                    shellyError = nil
                    isShellyConnected = true
                } catch {
                    snapshot = freshSnapshot
                    shellyError = "Shelly : \(error.localizedDescription)"
                    isShellyConnected = false
                }
            } else {
                snapshot = freshSnapshot
                SizingHistoryStore.record(snapshot: freshSnapshot, gridPowerWatts: nil)
                recentSamples = SizingHistoryStore.recentSamples()
                shellyError = nil
                isShellyConnected = false
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if let old = snapshot {
                snapshot = SolarFlowSnapshot(
                    solarPowerWatts: old.solarPowerWatts,
                    homePowerWatts: old.homePowerWatts,
                    batteryLevelPercent: old.batteryLevelPercent,
                    batteryPowerWatts: old.batteryPowerWatts,
                    connectionState: .disconnected,
                    updatedAt: old.updatedAt
                )
            }
        }
    }

    func loadHistory(period: ZendureHistoryService.Period) async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        historyError = nil
        history = []
        defer { isLoadingHistory = false }
        do {
            let zendureHistory = try await ZendureHistoryService(
                email: configuration.zendureEmail,
                password: configuration.zendurePassword
            ).fetch(period: period)
            let cloudShellyHistory = isShellyConfigured
                ? (try? await makeShellyService().fetchHistory(period: period))
                : nil
            history = zendureHistory.map { point in
                let end: Date
                if period == .year {
                    let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: point.date) ?? point.date
                    end = Calendar.current.date(byAdding: .day, value: -1, to: nextMonth) ?? point.date
                } else {
                    end = point.date
                }
                let key: Date
                if period == .year {
                    key = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: point.date)) ?? point.date
                } else {
                    key = Calendar.current.startOfDay(for: point.date)
                }
                let shelly = cloudShellyHistory?[key]
                    ?? (isShellyConfigured ? ShellyHistoryStore.energy(from: point.date, to: min(end, .now)) : nil)
                return EnergyHistoryDay(
                    date: point.date,
                    solar: point.solar,
                    home: point.home,
                    batteryInput: point.batteryInput,
                    batteryOutput: point.batteryOutput,
                    gridImport: shelly?.importedKWh,
                    gridExport: shelly?.exportedKWh
                )
            }
        } catch {
            historyError = error.localizedDescription
        }
    }

    func loadSizingAnalysis() async {
        guard !isLoadingSizing else { return }
        isLoadingSizing = true
        sizingError = nil
        defer { isLoadingSizing = false }
        do {
            let zendure = try await ZendureHistoryService(
                email: configuration.zendureEmail,
                password: configuration.zendurePassword
            ).fetch(period: .thirtyDays)
            let shelly = isShellyConfigured ? (try? await makeShellyService().fetchHistory(period: .thirtyDays)) : nil
            sizingHistory = zendure.map { point in
                let key = Calendar.current.startOfDay(for: point.date)
                let grid = shelly?[key]
                return EnergyHistoryDay(
                    date: point.date, solar: point.solar, home: point.home,
                    batteryInput: point.batteryInput, batteryOutput: point.batteryOutput,
                    gridImport: grid?.importedKWh, gridExport: grid?.exportedKWh
                )
            }
        } catch { sizingError = error.localizedDescription }
    }

    private func makeService() -> any SolarFlowService {
        if cloudService == nil || activeCloudKey != configuration.cloudKey {
            activeCloudKey = configuration.cloudKey
            cloudService = ZendureCloudService(cloudKey: configuration.cloudKey)
        }
        return cloudService!
    }

    private func makeShellyService() -> ShellyCloudService {
        ShellyCloudService(
            server: configuration.shellyServer,
            deviceID: configuration.shellyDeviceID,
            authKey: configuration.shellyAuthKey
        )
    }

    private static let defaults = UserDefaults.standard

    private static func load() -> CloudConfiguration {
        var value = CloudConfiguration()
        value.zendureEmail = defaults.string(forKey: "zendureEmail") ?? ""
        value.shellyServer = defaults.string(forKey: "shellyServer") ?? ""
        value.shellyDeviceID = defaults.string(forKey: "shellyDeviceID") ?? ""
        value.panelPowerWp = defaults.double(forKey: "panelPowerWp")
        value.batteryCapacityKWh = defaults.double(forKey: "batteryCapacityKWh")
        let minimumSOC = defaults.object(forKey: "minimumSOCPercent") as? Int
        value.minimumSOCPercent = minimumSOC ?? 10
        value.weatherLocation = defaults.string(forKey: "weatherLocation") ?? ""
        value.appearanceMode = defaults.string(forKey: "appearanceMode") ?? "automatic"
        value.updateFeedURL = defaults.string(forKey: "updateFeedURL") ?? "https://stephsabb.github.io/solarflow-monitor/appcast.xml"
        value.automaticallyChecksForUpdates = defaults.object(forKey: "automaticallyChecksForUpdates") as? Bool ?? true
        return value
    }

    private static func save(_ value: CloudConfiguration) {
        defaults.set(value.zendureEmail, forKey: "zendureEmail")
        defaults.set(value.shellyServer, forKey: "shellyServer")
        defaults.set(value.shellyDeviceID, forKey: "shellyDeviceID")
        defaults.set(value.panelPowerWp, forKey: "panelPowerWp")
        defaults.set(value.batteryCapacityKWh, forKey: "batteryCapacityKWh")
        defaults.set(value.minimumSOCPercent, forKey: "minimumSOCPercent")
        defaults.set(value.weatherLocation, forKey: "weatherLocation")
        defaults.set(value.appearanceMode, forKey: "appearanceMode")
        defaults.set(value.updateFeedURL, forKey: "updateFeedURL")
        defaults.set(value.automaticallyChecksForUpdates, forKey: "automaticallyChecksForUpdates")
        KeychainStore.saveSecrets(.init(
            cloudKey: value.cloudKey,
            zendurePassword: value.zendurePassword,
            shellyAuthKey: value.shellyAuthKey
        ))
    }
}

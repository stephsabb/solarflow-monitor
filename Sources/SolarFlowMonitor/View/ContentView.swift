import SwiftUI
import AppKit
import Charts

struct ContentView: View {
    @ObservedObject var model: SolarFlowViewModel
    @ObservedObject var updates: UpdateController
    @State private var showingSettings = false
    @State private var showingHistory = false

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(configuration: $model.configuration, onCancel: {
                    showingSettings = false
                }) {
                    showingSettings = false
                    model.restart()
                }
            } else {
                VStack(spacing: 10) {
                    header
                    recentCharts
                    WeatherCard(weather: model.weather, forecast: model.solarForecast, error: model.weatherError)
                    status
                }
                .padding(12)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(width: 360, height: 575)
        .preferredColorScheme(preferredColorScheme)
        .sheet(isPresented: $showingHistory) {
            HistoryView(model: model)
        }
        .task { model.start() }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.configuration.appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var header: some View {
        HStack {
            SolarPanelSymbol()
            VStack(alignment: .leading) {
                Text("SolarFlow").font(.title2.bold())
                Text("Accès cloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isRefreshing { ProgressView().controlSize(.small) }
            Button("Historique", systemImage: "chart.bar.xaxis") { showingHistory = true }
                .labelStyle(.iconOnly)
                .help("Historique des 7 derniers jours")
            Button("Configuration", systemImage: "gearshape") { showingSettings = true }
                .labelStyle(.iconOnly)
                .help("Configuration")
            Button("Rechercher les mises à jour", systemImage: "arrow.triangle.2.circlepath") {
                updates.checkForUpdates()
            }
            .labelStyle(.iconOnly)
            .help(updates.isConfigured ? "Rechercher les mises à jour" : "Configurez le catalogue dans Interface")
            .disabled(!updates.canCheckForUpdates)
            Button("Quitter", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .labelStyle(.iconOnly)
                .help("Quitter SolarFlow Monitor")
        }
    }

    private var metrics: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                MetricCard(title: "Production solaire", value: watts(model.snapshot?.solarPowerWatts), icon: "sun.max")
                MetricCard(
                    title: model.isShellyConnected ? "Consommation totale maison" : "Puissance fournie à la maison",
                    value: watts(model.snapshot?.homePowerWatts),
                    icon: "house"
                )
            }
            GridRow {
                MetricCard(title: "Niveau batterie", value: percent(model.snapshot?.batteryLevelPercent), icon: "battery.75percent")
                MetricCard(title: "Puissance batterie", value: batteryValue, subtitle: batteryDirection, icon: "bolt.fill")
            }
        }
    }

    private var status: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(model.snapshot?.connectionState == .connected ? .green : .red)
                    .frame(width: 9, height: 9)
                Text(model.snapshot?.connectionState == .connected ? "Connecté" : "Déconnecté")
                Spacer()
                Text("Màj : \(updatedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.shellyError {
                Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var recentCharts: some View {
        let solarPeak = Double(model.recentSamples.map(\.solarWatts).max() ?? 0)
        let scale = max(1_000, ceil(solarPeak / 1_000) * 1_000)
        let sharedPowerDomain = 0...scale
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Dernières 24 heures").font(.caption.bold())
                Spacer()
                Text("Relevés chaque minute").font(.caption2).foregroundStyle(.secondary)
            }
            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow {
                    MiniHistoryChart(title: "Solaire", icon: "sun.max.fill", unit: "W", color: .yellow, samples: model.recentSamples, fixedYDomain: sharedPowerDomain) { Double($0.solarWatts) }
                    MiniHistoryChart(title: "Maison", icon: "house.fill", unit: "W", color: .orange, samples: model.recentSamples, fixedYDomain: sharedPowerDomain) { Double($0.totalHomeWatts) }
                }
                GridRow {
                    MiniHistoryChart(title: "Batteries", icon: "battery.75percent", unit: "%", color: .green, samples: model.recentSamples, fixedYDomain: 0...100) { Double($0.socPercent) }
                    MiniHistoryChart(title: "Réseau", icon: "arrow.left.arrow.right", unit: "W", color: .blue, samples: model.recentSamples, fixedYDomain: sharedPowerDomain) { Double(max(0, $0.gridWatts ?? 0)) }
                }
            }
        }
    }

    private func watts(_ value: Int?) -> String { value.map { "\($0) W" } ?? "—" }
    private func percent(_ value: Int?) -> String { value.map { "\($0) %" } ?? "—" }
    private var batteryValue: String {
        guard let power = model.snapshot?.batteryPowerWatts else { return "—" }
        return watts(abs(power))
    }
    private var batteryDirection: String? {
        guard let power = model.snapshot?.batteryPowerWatts else { return nil }
        return power > 0 ? "En charge" : power < 0 ? "En décharge" : "Au repos"
    }
    private var updatedText: String {
        model.snapshot?.updatedAt.formatted(date: .omitted, time: .standard) ?? "—"
    }
}

private struct WeatherCard: View {
    let weather: WeatherSnapshot?
    let forecast: SolarProductionForecast?
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun.fill").foregroundStyle(.gray)
                Text("Météo locale").font(.caption.bold()).foregroundStyle(.primary)
                Spacer()
                if let weather { Text(weather.locationName).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
            }
            if let weather {
                HStack {
                    Image(systemName: weatherSymbol(weather.weatherCode)).font(.title3).foregroundStyle(weatherColor(weather.weatherCode))
                    Text(weatherDescription(weather.weatherCode)).font(.callout)
                    Spacer()
                    Text("\(Int(weather.temperatureCelsius.rounded())) °C").font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.primary)
                }
                WeatherLine(color: .gray, title: "Couverture nuageuse", value: "\(weather.cloudCoverPercent) %")
                WeatherLine(color: .yellow, title: "Ensoleillement prévu", value: sunshine(weather.sunshineDurationSeconds))
                if let forecast {
                    Divider()
                    HStack {
                        Label("Prévision solaire", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(energy(forecast.totalKWh)) aujourd’hui")
                            .font(.caption.bold().monospacedDigit())
                    }
                    Chart(forecast.points) { point in
                        AreaMark(
                            x: .value("Heure", point.date),
                            y: .value("Puissance prévue", point.watts)
                        )
                        .foregroundStyle(.linearGradient(
                            colors: [.yellow.opacity(0.08), .yellow.opacity(0.48)],
                            startPoint: .bottom,
                            endPoint: .top
                        ))
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value("Heure", point.date),
                            y: .value("Puissance prévue", point.watts)
                        )
                        .foregroundStyle(.yellow)
                        .interpolationMethod(.catmullRom)
                    }
                    .chartLegend(.hidden)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) {
                            AxisValueLabel(format: .dateTime.hour())
                            AxisTick()
                        }
                    }
                    .frame(height: 48)
                    HStack {
                        Text("Reste ≈ \(energy(forecast.remainingKWh))")
                        Spacer()
                        Text("Confiance : \(forecast.confidenceLabel.lowercased()) · \(forecast.calibrationDays) j")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Renseignez la puissance des panneaux pour activer la prévision solaire.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(error ?? "Renseignez une ville dans Configuration → Météo locale.")
                    .font(.caption).foregroundStyle(error == nil ? Color.secondary : Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: forecast == nil ? 92 : 174)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.55)))
    }

    private func sunshine(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    private func energy(_ kWh: Double) -> String {
        kWh.formatted(.number.precision(.fractionLength(1))) + " kWh"
    }
    private func weatherDescription(_ code: Int) -> String {
        switch code {
        case 0: "Ciel clair"
        case 1: "Peu nuageux"
        case 2: "Partiellement nuageux"
        case 3: "Couvert"
        case 45, 48: "Brouillard"
        case 51...57: "Bruine"
        case 61...67, 80...82: "Pluie"
        case 71...77, 85...86: "Neige"
        case 95...99: "Orage"
        default: "Conditions variables"
        }
    }
    private func weatherSymbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 71...77, 85...86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.sun.fill"
        }
    }
    private func weatherColor(_ code: Int) -> Color { code <= 2 ? .yellow : code >= 95 ? .purple : .blue }
}

private struct WeatherLine: View {
    let color: Color; let title: String; let value: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.caption)
    }
}

private struct SolarPanelSymbol: View {
    var body: some View {
        ZStack {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 17))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(-8))
            Image(systemName: "sun.max.fill")
                .font(.system(size: 13))
                .foregroundStyle(.yellow)
                .offset(x: 10, y: -10)
        }
        .frame(width: 30, height: 28)
        .accessibilityLabel("Panneau solaire")
    }
}

private struct MiniHistoryChart: View {
    let title: String
    let icon: String
    let unit: String
    let color: Color
    let samples: [SizingHistoryStore.Sample]
    var fixedYDomain: ClosedRange<Double>? = nil
    let value: (SizingHistoryStore.Sample) -> Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundStyle(.primary)
                Text(title).font(.caption.bold()).foregroundStyle(.primary)
                Spacer()
                Text(latestValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            if samples.count < 2 {
                Text("Collecte en cours…")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 105)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor).opacity(0.55)))
    }

    @ViewBuilder private var chart: some View {
        let content = Chart {
                    ForEach(smoothedPoints) { point in
                        LineMark(x: .value("Heure", point.date), y: .value(title, point.value))
                            .foregroundStyle(color)
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("Heure", point.date), yStart: .value("Zéro", 0), yEnd: .value(title, point.value))
                            .foregroundStyle(.linearGradient(
                                colors: [color.opacity(0.04), color.opacity(0.42)],
                                startPoint: .bottom,
                                endPoint: .top
                            ))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        if let fixedYDomain {
            content.chartYScale(domain: fixedYDomain)
        } else {
            content
        }
    }

    private var latestValue: String {
        guard let sample = samples.last else { return "— \(unit)" }
        return "\(Int(value(sample).rounded())) \(unit)"
    }

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Fifteen-sample centered moving average removes one-minute spikes while
    /// preserving the overall daily shape.
    private var smoothedPoints: [Point] {
        samples.indices.map { index in
            let lower = max(samples.startIndex, index - 7)
            let upper = min(samples.index(before: samples.endIndex), index + 7)
            let values = samples[lower...upper].map(value)
            return Point(date: samples[index].date, value: values.reduce(0, +) / Double(values.count))
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body).frame(width: 20).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(value).font(.headline.monospacedDigit().bold())
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 68)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

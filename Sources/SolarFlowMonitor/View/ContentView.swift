import SwiftUI
import AppKit
import Charts

struct ContentView: View {
    @ObservedObject var model: SolarFlowViewModel
    @ObservedObject var updates: UpdateController
    @State private var showingSettings = false
    @State private var showingHistory = false
    // Always reopen on the lightweight charts view. This also provides a safe
    // recovery path if the animated view is too demanding on a given Mac.
    @State private var mainDisplayMode = "charts"

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(configuration: $model.configuration, updates: updates, onCancel: {
                    showingSettings = false
                }) {
                    showingSettings = false
                    model.restart()
                }
            } else {
                VStack(spacing: 10) {
                    header
                    if mainDisplayMode == "flows" {
                        EnergyFlowView(snapshot: model.snapshot, gridPowerWatts: model.recentSamples.last?.gridWatts)
                    } else {
                        recentCharts
                        WeatherCard(weather: model.weather, forecast: model.solarForecast, error: model.weatherError)
                    }
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
                HStack(spacing: 6) {
                    Text("SolarFlow").font(.title2.bold())
                    Picker("Affichage principal", selection: $mainDisplayMode) {
                        Image(systemName: "chart.xyaxis.line").tag("charts")
                        Image(systemName: "point.3.connected.trianglepath.dotted").tag("flows")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 67)
                    .controlSize(.mini)
                    .tint(.orange)
                    .help("Basculer entre les courbes et les flux d’énergie")
                }
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

private struct EnergyFlowView: View {
    let snapshot: SolarFlowSnapshot?
    let gridPowerWatts: Int?
    @Environment(\.colorScheme) private var colorScheme

    private var solar: Int { max(0, snapshot?.solarPowerWatts ?? 0) }
    private var home: Int { max(0, snapshot?.homePowerWatts ?? 0) }
    private var battery: Int { snapshot?.batteryPowerWatts ?? 0 }
    private var grid: Int { gridPowerWatts ?? 0 }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let hub = CGPoint(x: size.width * 0.49, y: size.height * 0.61)
            let solarPoint = CGPoint(x: size.width / 2, y: 47)
            let gridPoint = CGPoint(x: 55, y: size.height - 76)
            let homePoint = CGPoint(x: size.width - 55, y: 76)
            let batteryPoint = CGPoint(x: size.width - 58, y: size.height - 48)

            ZStack {
                if let image = flowBackgroundImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                }

                EnergyFlowCables(cables: [
                    .init(points: [CGPoint(x: size.width * 0.50, y: size.height * 0.395), hub], color: .yellow, watts: solar, reversed: false),
                    .init(points: [CGPoint(x: size.width * 0.065, y: size.height * 0.70), CGPoint(x: size.width * 0.065, y: size.height * 0.77), CGPoint(x: size.width * 0.40, y: size.height * 0.77), hub], color: .blue, watts: abs(grid), reversed: grid < 0),
                    .init(points: [hub, CGPoint(x: size.width * 0.61, y: size.height * 0.68), CGPoint(x: size.width * 0.82, y: size.height * 0.625)], color: .cyan, watts: abs(battery), reversed: battery < 0)
                ])

                FlowNode(title: "Solaire", value: "\(solar) W")
                    .position(solarPoint)
                FlowNode(title: grid >= 0 ? "Depuis réseau" : "Vers réseau", value: "\(abs(grid)) W")
                    .position(gridPoint)
                FlowNode(title: "Maison", value: "\(home) W", color: .orange)
                    .position(homePoint)
                FlowNode(title: battery > 0 ? "En charge" : battery < 0 ? "En décharge" : "Batterie", value: batteryValue)
                    .position(batteryPoint)

            }
        }
        .padding(.horizontal, 4)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
    }

    private var batteryValue: String {
        let power = abs(battery)
        let level = snapshot.map { " · \($0.batteryLevelPercent)%" } ?? ""
        return "\(power) W\(level)"
    }

    private var flowBackgroundImage: NSImage? {
        colorScheme == .dark ? Self.darkBackground : Self.lightBackground
    }

    private static let lightBackground = loadBackground(named: "EnergyFlowHouseLight")
    private static let darkBackground = loadBackground(named: "EnergyFlowHouseDark")

    private static func loadBackground(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

private struct FlowNode: View {
    let title: String
    let value: String
    var color: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.65)
            Text(title).font(.caption2).opacity(0.72).lineLimit(1)
        }
        .foregroundStyle(color ?? (colorScheme == .dark ? Color(white: 0.82) : Color(white: 0.22)))
        .frame(width: 108, height: 50)
        .shadow(color: Color(nsColor: .windowBackgroundColor).opacity(0.95), radius: 3)
    }
}

private struct EnergyFlowCables: View {
    struct Cable {
        let points: [CGPoint]
        let color: Color
        let watts: Int
        let reversed: Bool
    }
    let cables: [Cable]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { timeline in
            Canvas { context, _ in
                for cable in cables {
                    draw(cable, at: timeline.date, in: &context)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ cable: Cable, at date: Date, in context: inout GraphicsContext) {
        let renderedPoints = roundedPoints(through: cable.points, radius: 12)
        let path = path(through: renderedPoints)
        context.stroke(
            path,
            with: .color(cable.color.opacity(cable.watts == 0 ? 0.14 : 0.34)),
            style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
        )
        guard cable.watts > 0 else { return }
        let speed = min(0.20, 0.055 + Double(cable.watts) / 10_000.0)
        let base = date.timeIntervalSinceReferenceDate * speed
        for index in 0..<3 {
            let phase = normalized(base + Double(index) / 3)
            let head = cable.reversed ? normalized(1 - phase) : phase
            drawTrail(head: head, reversed: cable.reversed, points: renderedPoints, color: cable.color, in: &context)
        }
    }

    private func drawTrail(head: Double, reversed: Bool, points: [CGPoint], color: Color, in context: inout GraphicsContext) {
        let segmentCount = 18
        let trailLength = 0.105
        let direction = reversed ? -1.0 : 1.0
        for index in 0..<segmentCount {
            let startOffset = trailLength * Double(index + 1) / Double(segmentCount)
            let endOffset = trailLength * Double(index) / Double(segmentCount)
            let startProgress = normalized(head - direction * startOffset)
            let endProgress = normalized(head - direction * endOffset)
            guard abs(startProgress - endProgress) < 0.5 else { continue }
            let start = sample(at: startProgress, on: points).point
            let end = sample(at: endProgress, on: points).point
            let brightness = 1 - Double(index) / Double(segmentCount)
            var segment = Path()
            segment.move(to: start)
            segment.addLine(to: end)
            context.stroke(
                segment,
                with: .color(color.opacity(0.13 * brightness)),
                style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                segment,
                with: .color(color.opacity(0.18 + 0.82 * brightness * brightness)),
                style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func roundedPoints(through points: [CGPoint], radius: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1], corner = points[index], next = points[index + 1]
            let incoming = hypot(corner.x - previous.x, corner.y - previous.y)
            let outgoing = hypot(next.x - corner.x, next.y - corner.y)
            let distance = min(radius, incoming / 2, outgoing / 2)
            guard incoming > 0, outgoing > 0 else { continue }
            let entry = CGPoint(
                x: corner.x - (corner.x - previous.x) / incoming * distance,
                y: corner.y - (corner.y - previous.y) / incoming * distance
            )
            let exit = CGPoint(
                x: corner.x + (next.x - corner.x) / outgoing * distance,
                y: corner.y + (next.y - corner.y) / outgoing * distance
            )
            result.append(entry)
            for step in 1...8 {
                let t = CGFloat(step) / 8
                let inverse = 1 - t
                result.append(CGPoint(
                    x: inverse * inverse * entry.x + 2 * inverse * t * corner.x + t * t * exit.x,
                    y: inverse * inverse * entry.y + 2 * inverse * t * corner.y + t * t * exit.y
                ))
            }
        }
        if let last = points.last { result.append(last) }
        return result
    }

    private func normalized(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }

    private func sample(at progress: Double, on points: [CGPoint]) -> (point: CGPoint, direction: CGVector) {
        guard points.count > 1 else { return (points.first ?? .zero, CGVector(dx: 1, dy: 0)) }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return (points[0], CGVector(dx: 1, dy: 0)) }
        var target = progress * total
        for index in lengths.indices {
            if target <= lengths[index] {
                let start = points[index], end = points[index + 1]
                let amount = target / lengths[index]
                let point = CGPoint(x: start.x + (end.x - start.x) * amount, y: start.y + (end.y - start.y) * amount)
                return (point, CGVector(dx: (end.x - start.x) / lengths[index], dy: (end.y - start.y) / lengths[index]))
            }
            target -= lengths[index]
        }
        let start = points[points.count - 2], end = points[points.count - 1]
        let length = max(0.001, hypot(end.x - start.x, end.y - start.y))
        return (end, CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length))
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

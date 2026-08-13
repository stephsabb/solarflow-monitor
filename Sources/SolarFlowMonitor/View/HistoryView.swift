import Charts
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: SolarFlowViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeriod: ZendureHistoryService.Period = .sevenDays

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Historique").font(.title2.bold())
                    Picker("Période", selection: $selectedPeriod) {
                        ForEach([ZendureHistoryService.Period.sevenDays, .month, .year]) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(.orange)
                    .labelsHidden()
                    .frame(width: 220)
                    .disabled(model.isLoadingHistory)
                }
                Spacer()
                Button("Actualiser", systemImage: "arrow.clockwise") { Task { await model.loadHistory(period: selectedPeriod) } }
                    .disabled(model.isLoadingHistory)
                    .labelStyle(.iconOnly)
                    .help("Actualiser")
                Button("Analyse", systemImage: "gauge.with.dots.needle.67percent") { model.showSizingAnalysis = true }
                    .help("Analyser le dimensionnement sur 30 jours")
                Button("Fermer", action: { dismiss() })
            }

            if model.isLoadingHistory && model.history.isEmpty {
                Spacer()
                ProgressView("Récupération des données…")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if let error = model.historyError, model.history.isEmpty {
                ContentUnavailableView("Historique indisponible", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                summary
                historyChart

                HStack(spacing: 10) {
                    Label("Équipement solaire", systemImage: "square.fill").foregroundStyle(.green)
                    Label("Production solaire", systemImage: "square.fill").foregroundStyle(.yellow)
                    Label(model.hasShellyHistory ? "Consommation totale" : "Vers la maison", systemImage: "circle.fill").foregroundStyle(.orange)
                }.font(.caption)

                HistoryTable(history: model.history, isYear: selectedPeriod == .year, hasShelly: model.hasShellyHistory)
            }
        }
        .padding(14)
        .frame(width: 516, height: 597)
        .task(id: selectedPeriod) { await model.loadHistory(period: selectedPeriod) }
        .sheet(isPresented: $model.showSizingAnalysis) { SizingAnalysisView(model: model) }
    }

    private var summary: some View {
        HStack(spacing: 6) {
            HistoryTotal(title: "Équipement solaire", value: energy(model.history.reduce(0) { $0 + $1.home }), icon: "bolt.house.fill", color: .green)
            HistoryTotal(
                title: model.hasShellyHistory ? "Total maison" : "Énergie fournie à la maison",
                value: energy(model.history.reduce(0) { $0 + ($1.totalHome ?? $1.home) }),
                icon: "house.fill",
                color: .orange
            )
            HistoryTotal(title: "Production solaire", value: energy(model.history.reduce(0) { $0 + $1.solar }), icon: "sun.max.fill", color: .yellow)
        }
    }

    private var historyChart: some View {
        Chart(model.history) { day in
            BarMark(
                x: .value("Période", day.date, unit: selectedPeriod == .year ? .month : .day),
                yStart: .value("Origine équipement", 0),
                yEnd: .value("Équipement solaire", day.home)
            )
                .foregroundStyle(.green.gradient)
            BarMark(
                x: .value("Période", day.date, unit: selectedPeriod == .year ? .month : .day),
                yStart: .value("Origine production", 0),
                yEnd: .value("Production solaire", day.solar)
            )
                .foregroundStyle(.yellow.gradient)
            LineMark(
                x: .value("Période", day.date, unit: selectedPeriod == .year ? .month : .day),
                y: .value("Maison", day.totalHome ?? day.home)
            )
                .foregroundStyle(.orange)
                .symbol(.circle)

            if selectedPeriod != .year,
               Calendar.current.isDateInToday(day.date),
               let forecast = model.solarForecast,
               forecast.remainingKWh > 0 {
                RectangleMark(
                    x: .value("Aujourd’hui", day.date, unit: .day),
                    yStart: .value("Production réalisée", day.solar),
                    yEnd: .value("Production prévue", day.solar + forecast.remainingKWh),
                    width: .ratio(0.72)
                )
                .foregroundStyle(.orange.opacity(0.18))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [5, 3]))
                .annotation(position: .top, spacing: 2) {
                    Text("+\(energy(forecast.remainingKWh)) prévu")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .chartLegend(.hidden)
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXAxis {
            if selectedPeriod == .year {
                AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.narrow)) }
            } else {
                AxisMarks(values: .automatic(desiredCount: selectedPeriod == .month ? 8 : 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) }
            }
        }
        .frame(height: 260)
    }

    private func energy(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " kWh"
    }

    private func periodLabel(_ date: Date) -> String {
        selectedPeriod == .year
            ? date.formatted(.dateTime.month(.wide).year())
            : date.formatted(.dateTime.weekday(.wide).day().month())
    }
}

private struct HistoryTable: View {
    let history: [EnergyHistoryDay]
    let isYear: Bool
    let hasShelly: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isYear ? "Mois" : "Date").frame(maxWidth: .infinity, alignment: .leading)
                Text(hasShelly ? "Total maison" : "Vers la maison").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Équipement solaire").frame(maxWidth: .infinity, alignment: .trailing)
                Text("Production solaire").frame(maxWidth: .infinity, alignment: .trailing)
                Color.clear.frame(width: 18, height: 1)
            }
            .font(.caption2.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(history) { day in
                        HistoryDisclosureRow(day: day, isYear: isYear, hasShelly: hasShelly)
                        Divider()
                    }
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}

private struct HistoryDisclosureRow: View {
    let day: EnergyHistoryDay
    let isYear: Bool
    let hasShelly: Bool
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } } label: {
                HStack {
                    Text(periodLabel).frame(maxWidth: .infinity, alignment: .leading)
                    Text(energy(day.totalHome ?? day.home)).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(energy(day.home)).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(energy(day.solar)).frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 18)
                }
                .contentShape(Rectangle())
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)

            if expanded {
                Grid(horizontalSpacing: 10, verticalSpacing: 5) {
                    GridRow {
                        DetailMetric(title: "Production solaire", value: energy(day.solar))
                        DetailMetric(title: "Import réseau", value: day.gridImport.map(energy) ?? "—")
                        DetailMetric(title: "Injection", value: day.gridExport.map(energy) ?? "—")
                    }
                    GridRow {
                        DetailMetric(title: "Vers batteries", value: energy(day.batteryInput))
                        DetailMetric(title: "Depuis batteries", value: energy(day.batteryOutput))
                        DetailMetric(title: "Source du total", value: hasShelly ? "Zendure + Shelly" : "Zendure")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var periodLabel: String {
        isYear
            ? day.date.formatted(.dateTime.month(.wide).year())
            : day.date.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func energy(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2))) + " kWh"
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit()).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryTotal: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline.monospacedDigit())
            }
            Spacer()
        }
        .padding(7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

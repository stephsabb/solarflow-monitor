import SwiftUI

struct SizingAnalysisView: View {
    @ObservedObject var model: SolarFlowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dimensionnement").font(.title2.bold())
                    Text("Analyse des 30 derniers jours").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Actualiser", systemImage: "arrow.clockwise") { Task { await model.loadSizingAnalysis() } }
                    .disabled(model.isLoadingSizing)
                Button("Fermer") { dismiss() }
            }

            if model.isLoadingSizing && model.sizingHistory.isEmpty {
                Spacer(); ProgressView("Récupération des données…").frame(maxWidth: .infinity); Spacer()
            } else if let error = model.sizingError, model.sizingHistory.isEmpty {
                ContentUnavailableView("Analyse indisponible", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                energyCards
                Divider()
                liveIndicators
                diagnosis
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
        .task { await model.loadSizingAnalysis() }
    }

    private var totals: (solar: Double, home: Double, charge: Double, discharge: Double, imported: Double, exported: Double) {
        model.sizingHistory.reduce(into: (0, 0, 0, 0, 0, 0)) { value, day in
            value.0 += day.solar; value.1 += day.totalHome ?? day.home
            value.2 += day.batteryInput; value.3 += day.batteryOutput
            value.4 += day.gridImport ?? 0; value.5 += day.gridExport ?? 0
        }
    }

    private var energyCards: some View {
        let value = totals
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                AnalysisMetric("Production solaire", energy(value.solar), color: .yellow)
                AnalysisMetric("Total maison", energy(value.home), color: .orange)
                AnalysisMetric("Vers batteries", energy(value.charge), color: .green)
            }
            GridRow {
                AnalysisMetric("Import réseau", energy(value.imported), color: .red)
                AnalysisMetric("Injection", energy(value.exported), color: .blue)
                AnalysisMetric("Autoconsommation", percent(value.solar > 0 ? max(0, 1 - value.exported / value.solar) : 0), color: .mint)
            }
        }
    }

    private var liveIndicators: some View {
        let values = SizingHistoryStore.indicators(minimumSOC: model.configuration.minimumSOCPercent)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Comportement des batteries").font(.headline)
            Text("SOC (State of Charge) : niveau de charge restant de la batterie, exprimé en pourcentage.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Couverture locale : \(values.coverageDays) jour(s), \(values.sampledHours.formatted(.number.precision(.fractionLength(1)))) h mesurées")
                .font(.caption).foregroundStyle(values.coverageDays >= 20 ? Color.secondary : Color.orange)
            Grid(horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow { Text("Pleine avec production solaire"); Text("\(values.fullWithSolarHours.formatted(.number.precision(.fractionLength(1)))) h · \(values.fullDays) j").monospacedDigit() }
                GridRow { Text("SOC minimal avec import réseau"); Text("\(values.minimumWithImportHours.formatted(.number.precision(.fractionLength(1)))) h").monospacedDigit() }
                GridRow { Text("SOC minimal après 18 h"); Text("\(values.minimumEveningDays) jour(s)").monospacedDigit() }
            }.font(.callout)
            if values.coverageDays < 20 {
                Label("Laissez l’application fonctionner régulièrement : un diagnostic horaire fiable demande idéalement 20 à 30 jours de mesures.", systemImage: "clock")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var diagnosis: some View {
        let value = totals
        let samples = SizingHistoryStore.indicators(minimumSOC: model.configuration.minimumSOCPercent)
        let exportRate = value.solar > 0 ? value.exported / value.solar : 0
        let text: String
        if samples.coverageDays < 20 {
            text = exportRate >= 0.15
                ? "Une part notable de la production est injectée. Une capacité supplémentaire peut être intéressante, mais les mesures de SOC sont encore insuffisantes pour conclure."
                : "Aucun sous-dimensionnement évident dans les totaux énergétiques. Le diagnostic sera affiné lorsque davantage de mesures de SOC auront été enregistrées."
        } else if samples.fullDays >= 10 && samples.minimumEveningDays >= 5 {
            text = "La batterie est souvent pleine avec du solaire puis atteint fréquemment son minimum le soir : la capacité de stockage paraît probablement insuffisante."
        } else if samples.fullDays <= 2 {
            text = "La batterie atteint rarement 100 % : augmenter sa capacité semble peu utile avec la production actuelle."
        } else if samples.minimumEveningDays >= 8 {
            text = "La batterie atteint régulièrement son minimum dès le soir : une capacité supplémentaire pourrait réduire l’import réseau nocturne."
        } else {
            text = "Le comportement observé paraît équilibré pour cette période. À confirmer sur une autre saison."
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text("Diagnostic indicatif").font(.headline)
            Text(text).font(.callout)
            Text("Le résultat dépend de la saison et ne constitue pas encore une simulation économique.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func energy(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) + " kWh" }
    private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0))) }
}

private struct AnalysisMetric: View {
    let title: String; let value: String; let color: Color
    init(_ title: String, _ value: String, color: Color) { self.title = title; self.value = value; self.color = color }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
    }
}

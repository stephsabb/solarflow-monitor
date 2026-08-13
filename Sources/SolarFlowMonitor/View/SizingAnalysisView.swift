import SwiftUI

struct SizingAnalysisView: View {
    @ObservedObject var model: SolarFlowViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyse de votre utilisation").font(.title2.bold())
                    Text("Analyse des 30 derniers jours").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
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
                AnalysisMetric("Consommation de la production", percent(value.solar > 0 ? max(0, 1 - value.exported / value.solar) : 0), color: .mint)
            }
        }
    }

    private var liveIndicators: some View {
        let values = SizingHistoryStore.indicators(minimumSOC: model.configuration.minimumSOCPercent)
        let coverage = values.sampledHours.formatted(.number.precision(.fractionLength(1)))
        let fullDuration = values.fullWithSolarHours.formatted(.number.precision(.fractionLength(1)))
        let minimumDuration = values.minimumWithImportHours.formatted(.number.precision(.fractionLength(1)))
        let minimum = model.configuration.minimumSOCPercent
        return VStack(alignment: .leading, spacing: 8) {
            Text("Lecture des résultats").font(.headline)
            ResultParagraph(
                icon: "calendar.badge.clock",
                color: .blue,
                text: "Les totaux énergétiques portent sur les 30 derniers jours. L’analyse détaillée des batteries repose, elle, sur \(coverage) heures enregistrées localement pendant \(values.coverageDays) jour(s), lorsque l’application fonctionnait et que le Mac n’était pas en veille."
            )
            ResultParagraph(
                icon: values.fullWithSolarHours > values.minimumWithImportHours ? "battery.100percent" : "battery.25percent",
                color: values.fullWithSolarHours > values.minimumWithImportHours ? .green : .orange,
                text: "Sur cette période, les batteries sont restées presque pleines avec une production solaire disponible pendant environ \(fullDuration) heure(s), réparties sur \(values.fullDays) jour(s). Elles ont atteint leur réserve minimale de \(minimum) % tout en important du réseau pendant environ \(minimumDuration) heure(s)."
            )
            ResultParagraph(
                icon: values.minimumEveningDays == 0 ? "moon.stars.fill" : "moon.fill",
                color: values.minimumEveningDays == 0 ? .indigo : .orange,
                text: values.minimumEveningDays == 0
                    ? "Aucune journée observée ne montre une batterie arrivée à sa réserve minimale après 18 h. Les périodes d’import constatées à la réserve minimale ont donc eu lieu plus tôt dans la journée."
                    : "La batterie a atteint sa réserve minimale après 18 h pendant \(values.minimumEveningDays) jour(s), ce qui peut révéler un stockage insuffisant pour couvrir la soirée."
            )
            if values.coverageDays < 20 {
                Label("Ces observations restent provisoires. Laissez l’application fonctionner régulièrement : une conclusion fiable demande idéalement 20 à 30 jours de mesures.", systemImage: "clock")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
                ? "Une part notable de la production est injectée. Une capacité supplémentaire peut être intéressante, mais les mesures du niveau de charge des batteries sont encore insuffisantes pour conclure."
                : "Aucun sous-dimensionnement évident dans les totaux énergétiques. Le diagnostic sera affiné lorsque davantage de mesures du niveau de charge des batteries auront été enregistrées."
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

private struct ResultParagraph: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
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

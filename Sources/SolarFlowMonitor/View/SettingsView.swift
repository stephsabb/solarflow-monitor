import SwiftUI
import MapKit

struct SettingsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case solar = "Équipement solaire"
        case home = "Énergie"
        case weather = "Météo"
        case interface = "Interface"
        var id: Self { self }
        var icon: String {
            switch self {
            case .solar: "square.grid.2x2.fill"
            case .home: "bolt.fill"
            case .weather: "cloud.sun.fill"
            case .interface: "display"
            }
        }
        var shortTitle: String {
            switch self {
            case .solar: "Solaire"
            case .home: "Énergie"
            case .weather: "Météo"
            case .interface: "Interface"
            }
        }
    }

    @State private var draft: CloudConfiguration
    @State private var selectedTab: Tab = .solar
    @ObservedObject var updates: UpdateController
    private let configuration: Binding<CloudConfiguration>
    let onCancel: () -> Void
    let onSave: () -> Void

    init(configuration: Binding<CloudConfiguration>, updates: UpdateController, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.configuration = configuration
        self.updates = updates
        self._draft = State(initialValue: configuration.wrappedValue)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(selectedTab.rawValue).font(.headline.bold()).foregroundStyle(.primary)
                HStack(spacing: 3) {
                    ForEach(Tab.allCases) { tab in
                        Button { selectedTab = tab } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 16))
                                    .frame(width: 20, height: 20)
                                Text(tab.shortTitle)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(height: 13)
                            }
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 45)
                            .contentShape(Rectangle())
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 8)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)

            Divider()

            Group {
                switch selectedTab {
                case .solar: solarTab
                case .home: homeTab
                case .weather: weatherTab
                case .interface: interfaceTab
                }
            }
            .padding(12)
            .offset(y: -9)
            .frame(maxWidth: .infinity, minHeight: 435, maxHeight: 435, alignment: .topLeading)
            .background(Color.primary.opacity(0.018))

            Divider()
            HStack {
                Button("Annuler", action: onCancel)
                Spacer()
                Button("Enregistrer") {
                    configuration.wrappedValue = draft
                    onSave()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)
        }
        .frame(width: 360, height: 575, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var solarTab: some View {
        VStack(alignment: .leading, spacing: 5) {
            SettingsSection(title: "Accès Zendure Cloud", icon: "cloud.fill") {
                SettingsField("Clé d’autorisation Cloud") { SecureField("Clé Zendure", text: $draft.cloudKey) }
                SettingsField("E-mail du compte") { TextField("nom@exemple.fr", text: $draft.zendureEmail) }
                SettingsField("Mot de passe") { SecureField("Mot de passe Zendure", text: $draft.zendurePassword) }
                Text("La clé Cloud alimente les mesures en direct. L’e-mail et le mot de passe donnent accès à l’historique Zendure.")
                    .settingsHelp()
            }
            SettingsSection(title: "Dimensionnement de l’installation", icon: "ruler.fill") {
                SettingsField("Puissance des panneaux (en Wc)") {
                    TextField("Wc", value: $draft.panelPowerWp, format: .number)
                }
                SettingsField("Capacité des batteries (en kWh)") {
                    TextField("kWh", value: $draft.batteryCapacityKWh, format: .number)
                }
                SettingsField("Capacité minimale restante des batteries") {
                    Stepper("\(draft.minimumSOCPercent) %", value: $draft.minimumSOCPercent, in: 0...50)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.10), lineWidth: 0.7))
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var homeTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(title: "Consommation totale de la maison", icon: "bolt.house.fill") {
                SettingsField("Serveur Shelly Cloud") { TextField("shelly-123-eu.shelly.cloud", text: $draft.shellyServer) }
                SettingsField("Device ID Shelly") { TextField("12 caractères", text: $draft.shellyDeviceID) }
                SettingsField("Clé d’authentification") { SecureField("Clé Shelly", text: $draft.shellyAuthKey) }
                Text("Le Shelly 3EM / Pro 3EM mesure l’importation et l’injection afin de calculer la consommation totale du logement.")
                    .settingsHelp()
            }
        }
    }

    private var weatherTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(title: "Météo locale", icon: "location.fill") {
                SettingsField("Ville ou code postal") { TextField("Ex. Rennes ou 35000", text: $draft.weatherLocation) }
                Text("La ville est recherchée par Open‑Meteo. Les conditions et l’ensoleillement prévu sont actualisés toutes les 30 minutes.")
                    .settingsHelp()
            }
            WeatherLocationMap(location: draft.weatherLocation)
        }
    }

    private var interfaceTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSection(title: "Apparence", icon: "circle.lefthalf.filled") {
                SettingsField("Mode d’affichage") {
                    Picker("Mode d’affichage", selection: $draft.appearanceMode) {
                        Text("Automatique").tag("automatic")
                        Text("Clair").tag("light")
                        Text("Sombre").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Text("Automatique suit l’apparence choisie dans les réglages de macOS.")
                    .settingsHelp()
            }
            SettingsSection(title: "Mises à jour", icon: "arrow.triangle.2.circlepath") {
                Toggle("Rechercher automatiquement les nouvelles versions", isOn: $draft.automaticallyChecksForUpdates)
                    .font(.caption)
                    .padding(.horizontal, 7)
                Button {
                    updates.checkForUpdates()
                } label: {
                    Label("Rechercher les mises à jour", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!updates.canCheckForUpdates)
            }
        }
    }

}

private struct WeatherLocationMap: View {
    let location: String
    @State private var place: WeatherLocation?
    @State private var weather: WeatherSnapshot?
    @State private var position: MapCameraPosition = .region(.init(
        center: .init(latitude: 46.6, longitude: 2.4),
        span: .init(latitudeDelta: 10.5, longitudeDelta: 10.5)
    ))

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Localisation", systemImage: "map.fill")
                .font(.subheadline.bold())
                .foregroundStyle(Color.primary.opacity(0.82))
            ZStack(alignment: .topLeading) {
                Map(position: $position, interactionModes: []) {
                    if let place {
                        Annotation(place.name, coordinate: .init(latitude: place.latitude, longitude: place.longitude)) {
                            ZStack {
                                Circle().fill(.white).frame(width: 16, height: 16)
                                Circle().fill(.blue).frame(width: 10, height: 10)
                            }
                            .shadow(radius: 2)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))

                if let weather {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: weatherSymbol(weather.weatherCode))
                                .foregroundStyle(weatherColor(weather.weatherCode))
                            Text(weatherDescription(weather.weatherCode)).font(.caption.bold())
                            Text("\(Int(weather.temperatureCelsius.rounded())) °C")
                                .font(.caption.bold().monospacedDigit())
                        }
                        Text("Nuages \(weather.cloudCoverPercent) % · Soleil \(sunshine(weather.sunshineDurationSeconds))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .padding(8)
                }
            }
            .frame(height: 185)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        }
        .task(id: location) {
            guard location.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
                place = nil
                weather = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let service = OpenMeteoService()
            async let foundLocation = try? service.locate(location)
            async let report = try? service.fetch(location: location, panelPowerWp: 0, samples: [])
            if let found = await foundLocation {
                place = found
                position = .region(.init(
                    center: .init(latitude: found.latitude, longitude: found.longitude),
                    span: .init(latitudeDelta: 10.5, longitudeDelta: 10.5)
                ))
            }
            weather = await report?.weather
        }
    }

    private func sunshine(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
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
        default: "Variable"
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

    private func weatherColor(_ code: Int) -> Color {
        code <= 2 ? .yellow : code >= 95 ? .purple : .blue
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(Color.primary.opacity(0.82))
            VStack(alignment: .leading, spacing: 7) { content }
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.055))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 0.7)
                }
        }
    }
}

private struct SettingsField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field
    init(_ label: String, @ViewBuilder field: () -> Field) { self.label = label; self.field = field() }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.62))
            field
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
    }
}

private extension View {
    func settingsHelp() -> some View { font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

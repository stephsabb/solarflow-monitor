import AppKit
import Combine
import SwiftUI

@main
struct SolarFlowMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = SolarFlowViewModel()
    private let updates = UpdateController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 575)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(model: model, updates: updates).frame(width: 360, height: 575)
        )

        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in self?.updateStatusBar(snapshot) }
            .store(in: &subscriptions)

        model.$configuration
            .map(\.appearanceMode)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in self?.applyAppearance(mode) }
            .store(in: &subscriptions)

        model.$configuration
            .map { ($0.updateFeedURL, $0.automaticallyChecksForUpdates) }
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] feedURL, automaticallyChecks in
                self?.updates.configure(feedURLString: feedURL, automaticallyChecks: automaticallyChecks)
            }
            .store(in: &subscriptions)

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.configuration.appearanceMode == "automatic" else { return }
                self.applyAppearance("automatic")
            }
        }

        updateStatusBar(nil)
        model.start()
    }

    private func applyAppearance(_ mode: String) {
        let appearance: NSAppearance
        switch mode {
        case "light": appearance = NSAppearance(named: .aqua)!
        case "dark": appearance = NSAppearance(named: .darkAqua)!
        default:
            let systemUsesDarkMode = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
            appearance = NSAppearance(named: systemUsesDarkMode ? .darkAqua : .aqua)!
        }
        NSApp.appearance = appearance
        popover.contentViewController?.view.appearance = appearance
        popover.contentViewController?.view.window?.appearance = appearance
        popover.contentViewController?.view.needsDisplay = true
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusBar(_ snapshot: SolarFlowSnapshot?) {
        guard let button = statusItem?.button else { return }
        let result = NSMutableAttributedString()
        appendText("☀️ \(watts(snapshot?.solarPowerWatts))   ", to: result, weight: .semibold)
        appendSymbol("battery.75percent", color: .systemGreen, to: result)
        appendText(" \(percent(snapshot?.batteryLevelPercent))   ", to: result)
        appendSymbol("house", color: .systemOrange, to: result)
        appendText(" \(watts(snapshot?.homePowerWatts))", to: result)
        button.image = nil
        button.title = ""
        button.attributedTitle = result
        button.toolTip = "SolarFlow Monitor"
    }

    private func appendText(
        _ text: String,
        to result: NSMutableAttributedString,
        weight: NSFont.Weight = .medium
    ) {
        result.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: weight),
                .foregroundColor: NSColor.labelColor
            ]
        ))
    }

    private func appendSymbol(_ name: String, color: NSColor, to result: NSMutableAttributedString) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(.init(hierarchicalColor: color))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: 18, height: 16)
        result.append(NSAttributedString(attachment: attachment))
    }

    private func watts(_ value: Int?) -> String { value.map { "\($0) W" } ?? "— W" }
    private func percent(_ value: Int?) -> String { value.map { "\($0) %" } ?? "— %" }
}

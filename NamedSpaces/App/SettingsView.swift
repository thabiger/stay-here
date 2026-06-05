import SwiftUI
import Core
import Activation

final class SettingsCoordinator: ObservableObject {
    let activationSettings: ActivationSettings
    let appearanceSettings: AppearanceSettings
    let spaceSwitcherSettings: SpaceSwitcherSettings
    let windowSwitcherSettings: WindowSwitcherSettings
    private let onAppearanceChange: () -> Void

    @Published var appearanceMode: AppearanceMode = .system
    @Published var dockClickInterceptionEnabled: Bool = true
    @Published var singleWindowAppBundleIDsText: String = ""
    @Published var spaceSwitcherShortcutText: String = ""
    @Published var windowSwitcherShortcutText: String = ""
    @Published var windowSwitcherShowMinimizedWindows: Bool = false
    @Published var windowSwitcherShowHiddenWindows: Bool = false
    @Published var hudDisplayDuration: Double = HUDSettings.shared.displayDuration

    init(
        activationSettings: ActivationSettings,
        appearanceSettings: AppearanceSettings = .shared,
        spaceSwitcherSettings: SpaceSwitcherSettings = .shared,
        windowSwitcherSettings: WindowSwitcherSettings = .shared,
        onAppearanceChange: @escaping () -> Void = {}
    ) {
        self.activationSettings = activationSettings
        self.appearanceSettings = appearanceSettings
        self.spaceSwitcherSettings = spaceSwitcherSettings
        self.windowSwitcherSettings = windowSwitcherSettings
        self.onAppearanceChange = onAppearanceChange
    }

    func load() {
        appearanceMode = appearanceSettings.mode
        dockClickInterceptionEnabled = activationSettings.dockClickInterceptionEnabled
        singleWindowAppBundleIDsText = ActivationSettings.serializeSingleWindowAppBundleIDs(activationSettings.singleWindowAppBundleIDs)
        spaceSwitcherShortcutText = spaceSwitcherSettings.shortcutText
        windowSwitcherShortcutText = windowSwitcherSettings.shortcutText
        windowSwitcherShowMinimizedWindows = windowSwitcherSettings.showMinimizedWindows
        windowSwitcherShowHiddenWindows = windowSwitcherSettings.showHiddenWindows
        hudDisplayDuration = HUDSettings.shared.displayDuration
    }

    func commitAll() {
        appearanceSettings.mode = appearanceMode
        activationSettings.dockClickInterceptionEnabled = dockClickInterceptionEnabled
        activationSettings.singleWindowAppBundleIDs = ActivationSettings.parseSingleWindowAppBundleIDs(from: singleWindowAppBundleIDsText)
        spaceSwitcherSettings.shortcutText = spaceSwitcherShortcutText
        windowSwitcherSettings.shortcutText = windowSwitcherShortcutText
        windowSwitcherSettings.showMinimizedWindows = windowSwitcherShowMinimizedWindows
        windowSwitcherSettings.showHiddenWindows = windowSwitcherShowHiddenWindows
        HUDSettings.shared.displayDuration = hudDisplayDuration
    }

    func applyAppearanceMode() {
        appearanceSettings.mode = appearanceMode
        onAppearanceChange()
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: SettingsCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Appearance")
                    .font(.headline)
                Picker("Appearance", selection: $coordinator.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("Choose one mode for the switchers, HUD, and other app popups.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Single Window Apps")
                    .font(.headline)
                TextEditor(text: $coordinator.singleWindowAppBundleIDsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                Text("One bundle identifier per line, for example `com.apple.Notes`. These apps will show the single-window hint instead of the normal new-window behavior.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Dock Click Interception")
                    .font(.headline)
                Toggle("Enable Dock click interception", isOn: $coordinator.dockClickInterceptionEnabled)
                Text("When enabled, regular Dock clicks are handled by Named Spaces for multi-window apps. Single-window apps are swallowed on a normal click and only use Named Spaces behavior when Option is held. When disabled, macOS handles Dock clicks normally.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Space Switcher Shortcut")
                    .font(.headline)
                TextField("option+tab", text: $coordinator.spaceSwitcherShortcutText)
                    .textFieldStyle(.roundedBorder)
                Text("This combo opens the space picker. Use modifier names like `option`, `shift`, `control`, `command` plus a key like `tab`, `space`, or a letter. Example: `control+space`.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Window Switcher Shortcut")
                    .font(.headline)
                TextField("command+tab", text: $coordinator.windowSwitcherShortcutText)
                    .textFieldStyle(.roundedBorder)
                Text("This combo opens the window picker for windows on the current Space. The default replaces the macOS app switcher, but you can change it to any supported shortcut.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Window Switcher")
                    .font(.headline)
                Toggle("Show minimized windows", isOn: $coordinator.windowSwitcherShowMinimizedWindows)
                Toggle("Show hidden windows", isOn: $coordinator.windowSwitcherShowHiddenWindows)
                Text("When enabled, the picker includes minimized or hidden windows that belong to the current Space.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Space Change HUD")
                    .font(.headline)
                HStack {
                    Slider(value: $coordinator.hudDisplayDuration, in: 0.5...6.0, step: 0.1)
                    Text(String(format: "%.1fs", coordinator.hudDisplayDuration))
                        .font(.callout.monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }
                Text("How long the popup stays visible after a space change.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 680)
        .onAppear {
            coordinator.load()
        }
        .onChange(of: coordinator.appearanceMode) { _ in
            coordinator.applyAppearanceMode()
        }
    }
}

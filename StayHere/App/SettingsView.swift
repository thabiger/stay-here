import SwiftUI
import Core
import Activation

final class SettingsCoordinator: ObservableObject {
    let settings: SettingsRepository
    private let onAppearanceChange: () -> Void

    @Published var appearanceMode: AppearanceMode = .system
    @Published var diagnosticsEnabled: Bool = false
    @Published var dockClickInterceptionEnabled: Bool = true
    @Published var singleWindowAppBundleIDsText: String = ""
    @Published var spaceSwitcherEnabled: Bool = true
    @Published var spaceSwitcherShortcutText: String = ""
    @Published var windowSwitcherEnabled: Bool = true
    @Published var windowSwitcherShortcutText: String = ""
    @Published var windowSwitcherTitleFormat: WindowSwitcherTitleFormat = .appNameOnly
    @Published var screenRecordingGranted: Bool = ScreenRecordingPermissionCheck.isGranted
    @Published var windowSwitcherShowMinimizedWindows: Bool = false
    @Published var windowSwitcherShowHiddenWindows: Bool = false
    @Published var hudDisplayDuration: Double = 1.8

    init(
        settings: SettingsRepository,
        onAppearanceChange: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.onAppearanceChange = onAppearanceChange
    }

    func load() {
        appearanceMode = settings.appearanceMode
        diagnosticsEnabled = settings.diagnosticsEnabled
        dockClickInterceptionEnabled = settings.activationDockClickInterceptionEnabled
        singleWindowAppBundleIDsText = SingleWindowAppBundleIDList.serialize(settings.activationSingleWindowAppBundleIDs)
        spaceSwitcherEnabled = settings.spaceSwitcherEnabled
        spaceSwitcherShortcutText = settings.spaceSwitcherShortcutText
        windowSwitcherEnabled = settings.windowSwitcherEnabled
        windowSwitcherShortcutText = settings.windowSwitcherShortcutText
        windowSwitcherTitleFormat = settings.windowSwitcherTitleFormat
        screenRecordingGranted = ScreenRecordingPermissionCheck.isGranted
        windowSwitcherShowMinimizedWindows = settings.windowSwitcherShowMinimizedWindows
        windowSwitcherShowHiddenWindows = settings.windowSwitcherShowHiddenWindows
        hudDisplayDuration = settings.hudDisplayDuration
    }

    func commitAll() {
        settings.appearanceMode = appearanceMode
        settings.diagnosticsEnabled = diagnosticsEnabled
        settings.activationDockClickInterceptionEnabled = dockClickInterceptionEnabled
        settings.activationSingleWindowAppBundleIDs = SingleWindowAppBundleIDList.parse(singleWindowAppBundleIDsText)
        settings.spaceSwitcherEnabled = spaceSwitcherEnabled
        settings.spaceSwitcherShortcutText = spaceSwitcherShortcutText
        settings.windowSwitcherEnabled = windowSwitcherEnabled
        settings.windowSwitcherShortcutText = windowSwitcherShortcutText
        settings.windowSwitcherTitleFormat = windowSwitcherTitleFormat
        settings.windowSwitcherShowMinimizedWindows = windowSwitcherShowMinimizedWindows
        settings.windowSwitcherShowHiddenWindows = windowSwitcherShowHiddenWindows
        settings.hudDisplayDuration = hudDisplayDuration
    }

    func applyAppearanceMode() {
        settings.appearanceMode = appearanceMode
        onAppearanceChange()
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: SettingsCoordinator

    var body: some View {
        ScrollView {
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
                    Text("Diagnostics")
                        .font(.headline)
                    Toggle("Enable diagnostics", isOn: $coordinator.diagnosticsEnabled)
                    Text("When enabled, StayHere shows the Debug menu and writes verbose logs. Leave this off for normal use.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Warning: log entries may include bundle IDs, space names, and window titles. The log file is restricted to your user account (0o600).")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("Open Logs") {
                        Logger.shared.openLogsInFinder()
                    }
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
                    Text("When enabled, regular Dock clicks are handled by StayHere for multi-window apps. Single-window apps are swallowed on a normal click and only use StayHere behavior when Option is held. When disabled, macOS handles Dock clicks normally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Space Switcher Shortcut")
                        .font(.headline)
                    Toggle("Enable Space Switcher", isOn: $coordinator.spaceSwitcherEnabled)
                    TextField("command+tab", text: $coordinator.spaceSwitcherShortcutText)
                        .textFieldStyle(.roundedBorder)
                    Text("This combo opens the space picker. Use modifier names like `option`, `shift`, `control`, `command` plus a key like `tab`, `space`, or a letter. Example: `control+space`.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Window Switcher Shortcut")
                        .font(.headline)
                    Toggle("Enable Window Switcher", isOn: $coordinator.windowSwitcherEnabled)
                    TextField("command+`", text: $coordinator.windowSwitcherShortcutText)
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
                    Picker("Window row titles", selection: $coordinator.windowSwitcherTitleFormat) {
                        ForEach(WindowSwitcherTitleFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("When enabled, the picker includes minimized or hidden windows that belong to the current Space.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Choose whether rows show only the app name or `App Name: Window Title` when a window title is available.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if coordinator.windowSwitcherTitleFormat == .appNameAndWindowTitle && !coordinator.screenRecordingGranted {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Screen Recording is needed to show window titles. macOS hides window names from `CGWindowListCopyWindowInfo` until the app is approved.")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.red)
                            Button("Open Screen Recording Settings") {
                                ScreenRecordingPermissionCheck.openSettings()
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 640, minHeight: 720)
        .onAppear {
            coordinator.load()
        }
        .onChange(of: coordinator.appearanceMode) { _ in
            coordinator.applyAppearanceMode()
        }
    }
}

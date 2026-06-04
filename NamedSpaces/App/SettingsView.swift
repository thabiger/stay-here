import SwiftUI
import Core
import Activation

struct SpaceNameRow: Identifiable, Equatable {
    let id: Int
    let desktopLabel: String
}

final class SettingsCoordinator: ObservableObject {
    private let registry: SpaceRegistry
    let activationSettings: ActivationSettings
    let appearanceSettings: AppearanceSettings
    let spaceSwitcherSettings: SpaceSwitcherSettings
    let windowSwitcherSettings: WindowSwitcherSettings

    @Published var rows: [SpaceNameRow] = []
    @Published var draftNames: [Int: String] = [:]
    @Published var appearanceMode: AppearanceMode = .system
    @Published var dockClickInterceptionEnabled: Bool = true
    @Published var singleWindowAppBundleIDsText: String = ""
    @Published var spaceSwitcherShortcutText: String = ""
    @Published var windowSwitcherShortcutText: String = ""
    @Published var windowSwitcherShowMinimizedWindows: Bool = false
    @Published var windowSwitcherShowHiddenWindows: Bool = false
    @Published var hudDisplayDuration: Double = HUDSettings.shared.displayDuration

    init(
        registry: SpaceRegistry,
        activationSettings: ActivationSettings,
        appearanceSettings: AppearanceSettings = .shared,
        spaceSwitcherSettings: SpaceSwitcherSettings = .shared,
        windowSwitcherSettings: WindowSwitcherSettings = .shared
    ) {
        self.registry = registry
        self.activationSettings = activationSettings
        self.appearanceSettings = appearanceSettings
        self.spaceSwitcherSettings = spaceSwitcherSettings
        self.windowSwitcherSettings = windowSwitcherSettings
    }

    func load() {
        rows = registry.orderedSpaceIDs().map { id in
            SpaceNameRow(id: id, desktopLabel: registry.namespaceLabel(for: id))
        }
        draftNames = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, registry.name(for: $0.id)) })
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
        for row in rows {
            let value = draftNames[row.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalized = value.isEmpty ? "Unnamed space" : value
            registry.rename(spaceID: row.id, name: normalized)
            draftNames[row.id] = registry.name(for: row.id)
        }
        appearanceSettings.mode = appearanceMode
        activationSettings.dockClickInterceptionEnabled = dockClickInterceptionEnabled
        activationSettings.singleWindowAppBundleIDs = ActivationSettings.parseSingleWindowAppBundleIDs(from: singleWindowAppBundleIDsText)
        spaceSwitcherSettings.shortcutText = spaceSwitcherShortcutText
        windowSwitcherSettings.shortcutText = windowSwitcherShortcutText
        windowSwitcherSettings.showMinimizedWindows = windowSwitcherShowMinimizedWindows
        windowSwitcherSettings.showHiddenWindows = windowSwitcherShowHiddenWindows
        HUDSettings.shared.displayDuration = hudDisplayDuration
        registry.persistNow()
    }

    func moveRows(from source: IndexSet, to destination: Int) {
        registry.moveDisplayOrder(fromOffsets: source, toOffset: destination)
        let ids = registry.orderedSpaceIDs()
        rows = ids.map { id in
            SpaceNameRow(id: id, desktopLabel: registry.namespaceLabel(for: id))
        }
        for id in ids where draftNames[id] == nil {
            draftNames[id] = registry.name(for: id)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: SettingsCoordinator
    @FocusState private var focusedSpaceID: Int?

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

            Text("Space Names")
                .font(.title2.weight(.semibold))

            List {
                ForEach(coordinator.rows) { row in
                    HStack(spacing: 10) {
                        Text(row.desktopLabel)
                            .frame(width: 160, alignment: .leading)
                        TextField("Unnamed space", text: Binding(
                            get: { coordinator.draftNames[row.id, default: "Unnamed space"] },
                            set: { coordinator.draftNames[row.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedSpaceID, equals: row.id)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedSpaceID = row.id
                    }
                }
                .onMove(perform: coordinator.moveRows)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Text("Reorder changes app display order only; Mission Control order remains managed by macOS.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
    }
}

private extension Dictionary {
    subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        get { self[key] ?? defaultValue() }
        set { self[key] = newValue }
    }
}

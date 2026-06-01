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

    @Published var rows: [SpaceNameRow] = []
    @Published var draftNames: [Int: String] = [:]
    @Published var activationMode: ActivationMode = .replaceDockClicks

    init(registry: SpaceRegistry, activationSettings: ActivationSettings) {
        self.registry = registry
        self.activationSettings = activationSettings
    }

    func load() {
        rows = registry.orderedSpaceIDs().map { id in
            SpaceNameRow(id: id, desktopLabel: registry.namespaceLabel(for: id))
        }
        draftNames = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, registry.name(for: $0.id)) })
        activationMode = activationSettings.mode
    }

    func commitAll() {
        for row in rows {
            let value = draftNames[row.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalized = value.isEmpty ? "Unnamed space" : value
            registry.rename(spaceID: row.id, name: normalized)
            draftNames[row.id] = registry.name(for: row.id)
        }
        activationSettings.mode = activationMode
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    }
                }
                .onMove(perform: coordinator.moveRows)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Text("Reorder changes app display order only; Mission Control order remains managed by macOS.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Dock Click Interception")
                    .font(.headline)
                Picker("Interception mode", selection: $coordinator.activationMode) {
                    ForEach(ActivationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
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

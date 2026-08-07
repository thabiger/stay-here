import Foundation

@MainActor
public final class SpaceLabelStore {
    public private(set) var records: [Int: SpaceLabelRecord]
    public var labels: [Int: SpaceLabel] { records.mapValues(\.label) }
    public var spaceDisplayByID: [Int: String] { records.compactMapValues(\.display) }

    /// Prune only after the space has been absent from this many observations
    /// (observation cadence = every applied non-empty, non-stale, non-retained
    /// snapshot) IN WHICH its recorded display was observed. Deliberately decoupled
    /// from `SpaceStateManager.maxConsecutiveAnomalyRetentions` (= 3).
    public static let maxAbsenceObservationsBeforePrune = 5
    /// Wall-clock floor: the budget cannot complete until at least this much time has
    /// elapsed since the space's first absence observation. Protects slow Mission
    /// Control transitions / enumeration lag (0.2 s poll cadence cannot exhaust the
    /// budget in under a second).
    public static let minimumAbsenceDurationBeforePrune: TimeInterval = 2.0
    /// CGS omits the `Display Identifier` for some displays; associations for this
    /// sentinel cannot be positively confirmed, so labels on it are never counted or
    /// pruned. Policy lives in the domain (was `CGSBridge.unknownDisplayFallback`).
    /// `nonisolated` so the nonisolated `CGSBridge.managedSnapshot()` can read it.
    public nonisolated static let unknownDisplayIdentifier = "unknown-display"
    private static let persistDebounceNanoseconds: UInt64 = 200_000_000

    private let store: SpaceStore
    private let logger: any Logging
    private let now: () -> Date
    private var pendingPersistTask: Task<Void, Never>?
    /// Per-display space ID sets from the last observation. When the current set
    /// is a strict superset of the previous set (spaces are still being added —
    /// enumeration lag, hot-plug), absence counting is skipped on that display.
    private var previousSpacesByDisplay: [String: Set<Int>] = [:]

    public init(
        store: SpaceStore = SpaceStore(),
        logger: any Logging,
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.logger = logger
        self.now = now

        self.records = store.load().records
    }

    public func rename(spaceID: Int, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? SpaceDisplayNameProvider.defaultUnnamedName : trimmed

        if records[spaceID]?.label.name == normalized {
            return
        }

        var record = records[spaceID] ?? SpaceLabelRecord(
            label: SpaceLabel(name: normalized)
        )
        record.label = SpaceLabel(name: normalized)
        records[spaceID] = record
        persistDebounced()
    }

    /// Observation of one applied snapshot (full universe, all displays).
    /// - Present spaces: ensure default label, update display association, reset absence evidence.
    /// - Absent spaces whose recorded display IS observed: accumulate absence evidence.
    /// - Absent spaces whose recorded display is NOT observed (display-level gap): RESET evidence.
    /// - Absent spaces with nil/unknown recorded display: never counted, never pruned.
    /// Prune only when `absenceCount >= maxAbsenceObservationsBeforePrune` AND
    /// `now - firstAbsenceAt >= minimumAbsenceDurationBeforePrune`.
    public func observe(spaces: [SpaceIdentity], observedDisplays: Set<String>) {
        guard !spaces.isEmpty else { return } // empty observation never counts or prunes

        let timestamp = now()
        var updated = records
        var changed = false
        let presentIDs = Set(spaces.map(\.id))

        // Detect displays whose space set is still growing (strict superset of the
        // previous observation). Growing is the hallmark of transiently-partial
        // snapshots: CGS hot-plug enumeration, sleep/wake re-enumeration, or general
        // enumeration lag where spaces appear gradually. Absence counting is skipped
        // on growing displays to prevent transient-partial snapshots from exhausting
        // the observation budget and pruning labels prematurely.
        var currentSpacesByDisplay: [String: Set<Int>] = [:]
        for space in spaces {
            currentSpacesByDisplay[space.display, default: []].insert(space.id)
        }
        let growingDisplays: Set<String> = Set(
            currentSpacesByDisplay.compactMap { display, currentIDs -> String? in
                guard let previousIDs = previousSpacesByDisplay[display],
                      currentIDs != previousIDs,
                      currentIDs.isSuperset(of: previousIDs) else { return nil }
                return display
            }
        )

        for space in spaces {
            var record = updated[space.id] ?? SpaceLabelRecord(
                label: SpaceLabel(name: SpaceDisplayNameProvider.defaultUnnamedName),
                display: space.display
            )
            if updated[space.id] == nil { changed = true }
            if record.display != space.display {
                record.display = space.display
                changed = true
            }
            record.absenceCount = 0
            record.firstAbsenceAt = nil
            updated[space.id] = record
        }

        // Materialize absent keys up front: mutating `updated` while enumerating
        // its keys would trap at runtime.
        let absentKeys = updated.keys.filter { !presentIDs.contains($0) }
        for key in absentKeys {
            guard var record = updated[key],
                  let display = record.display,
                  display != Self.unknownDisplayIdentifier
            else { continue } // cannot positively confirm removal

            guard observedDisplays.contains(display) else {
                // Display-level gap (display absent from snapshot): reset stale evidence.
                if record.absenceCount != 0 || record.firstAbsenceAt != nil {
                    record.absenceCount = 0
                    record.firstAbsenceAt = nil
                    updated[key] = record
                    changed = true
                }
                continue
            }

            guard !growingDisplays.contains(display) else {
                // Display is still growing → snapshot is transiently partial for this
                // display. Do not advance absence evidence; the missing spaces may
                // reappear once enumeration finishes.
                continue
            }

            if record.firstAbsenceAt == nil { record.firstAbsenceAt = timestamp }
            record.absenceCount += 1
            if record.absenceCount >= Self.maxAbsenceObservationsBeforePrune,
               let first = record.firstAbsenceAt,
               timestamp.timeIntervalSince(first) >= Self.minimumAbsenceDurationBeforePrune {
                updated.removeValue(forKey: key)
                changed = true
            } else {
                updated[key] = record
            }
        }

        previousSpacesByDisplay = currentSpacesByDisplay
        records = updated
        guard changed else { return }
        persistDebounced()
    }

    public func persistNow() {
        pendingPersistTask?.cancel()
        pendingPersistTask = nil

        do {
            try store.save(PersistedSpaces(records: records))
        } catch {
            logger.error("persist-failed")
        }
    }

    func persistenceSnapshot() -> [Int: SpaceLabel] {
        labels
    }

    private func persistDebounced() {
        pendingPersistTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: Self.persistDebounceNanoseconds)
            guard !Task.isCancelled else { return }

            do {
                try self.store.save(PersistedSpaces(records: self.records))
            } catch {
                self.logger.error("persist-failed")
            }
        }
        pendingPersistTask = task
    }
}

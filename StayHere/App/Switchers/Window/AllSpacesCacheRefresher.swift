import Core
import Foundation

@MainActor
final class AllSpacesCacheRefresher {
    private let computerFactory: @MainActor () -> AllSpacesWindowComputer
    private let onCompletion: @MainActor ([SpaceWindowGroup], Int) -> Void
    private let generationProvider: @MainActor () -> Int

    private enum RefreshState {
        case idle
        case refreshing(task: Task<[SpaceWindowGroup]?, Never>, id: Int, generation: Int)
        case pending(task: Task<[SpaceWindowGroup]?, Never>, id: Int, generation: Int)
    }

    private var state: RefreshState = .idle
    private var nextTaskID = 0
    private var idleContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        computerFactory: @escaping @MainActor () -> AllSpacesWindowComputer,
        onCompletion: @escaping @MainActor ([SpaceWindowGroup], Int) -> Void,
        generationProvider: @escaping @MainActor () -> Int = { 0 }
    ) {
        self.computerFactory = computerFactory
        self.onCompletion = onCompletion
        self.generationProvider = generationProvider
    }

    func refresh() {
        switch state {
        case .idle:
            startRefresh()
        case .refreshing(let task, let id, let generation):
            state = .pending(task: task, id: id, generation: generation)
        case .pending:
            break
        }
    }

    private func startRefresh() {
        let computer = computerFactory()
        nextTaskID += 1
        let id = nextTaskID
        let generation = generationProvider()
        let task = Task.detached(priority: .userInitiated) { () -> [SpaceWindowGroup]? in
            guard !Task.isCancelled else { return nil }
            let groups = computer.compute()
            guard !Task.isCancelled else { return nil }
            return groups
        }
        state = .refreshing(task: task, id: id, generation: generation)
        observe(task, id: id)
    }

    private func observe(_ task: Task<[SpaceWindowGroup]?, Never>, id: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let groups = await task.value
            switch self.state {
            case .refreshing(_, let currentID, let generation):
                // Stale callback (from a cancelled/superseded task) must not
                // corrupt the state machine.
                guard currentID == id else { return }
                if let groups {
                    self.onCompletion(groups, generation)
                }
                self.handleCompletion()
            case .pending(_, let pendingID, let generation):
                // A refresh() request arrived while this task was in flight, so
                // the state moved to .pending before this callback ran. The
                // completing task is still the current one: deliver its result
                // and let handleCompletion start the coalesced follow-up.
                guard pendingID == id else { return }
                if let groups {
                    self.onCompletion(groups, generation)
                }
                self.handleCompletion()
            case .idle:
                break
            }
        }
    }

    private func handleCompletion() {
        switch state {
        case .idle:
            break
        case .refreshing:
            state = .idle
            resumeIdleContinuations()
        case .pending:
            startRefresh()
        }
    }

    private func resumeIdleContinuations() {
        let continuations = idleContinuations
        idleContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func cancel() {
        switch state {
        case .refreshing(let task, _, _), .pending(let task, _, _):
            task.cancel()
        case .idle:
            break
        }
        state = .idle
        resumeIdleContinuations()
    }

    func waitForIdle() async {
        if case .idle = state { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            idleContinuations.append(continuation)
        }
    }
}

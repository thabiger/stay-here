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
        case pending
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
        case .refreshing:
            state = .pending
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
            guard (try? Task.checkCancellation()) != nil else { return nil }
            let groups = computer.compute()
            guard (try? Task.checkCancellation()) != nil else { return nil }
            return groups
        }
        state = .refreshing(task: task, id: id, generation: generation)
        observe(task, id: id)
    }

    private func observe(_ task: Task<[SpaceWindowGroup]?, Never>, id: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let groups = await task.value
            // Only process if this task is still the current refresh task.
            // A stale callback (from a cancelled/superseded task) must not
            // corrupt the state machine.
            guard case .refreshing(_, let currentID, let generation) = self.state, currentID == id else {
                return
            }
            if let groups {
                self.onCompletion(groups, generation)
            }
            self.handleCompletion()
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
        if case .refreshing(let task, _, _) = state {
            task.cancel()
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

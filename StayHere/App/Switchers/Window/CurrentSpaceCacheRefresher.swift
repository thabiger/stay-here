import Core
import Foundation

@MainActor
final class CurrentSpaceCacheRefresher {
    private let computerFactory: @MainActor (WindowSpaceContext) -> CurrentSpaceWindowComputer
    private let onCompletion: @MainActor (WindowSpaceContext, [WindowEntry], Int) -> Void
    private var onNotify: ((WindowSpaceContext) -> Void)?
    private let generationProvider: @MainActor () -> Int

    private enum RefreshState {
        case idle
        case refreshing(task: Task<[WindowEntry]?, Never>, id: Int, generation: Int, context: WindowSpaceContext)
        case pending(task: Task<[WindowEntry]?, Never>, id: Int, generation: Int,
                     taskContext: WindowSpaceContext, nextContext: WindowSpaceContext)
    }

    private var state: RefreshState = .idle
    private var nextTaskID = 0
    private var idleContinuations: [CheckedContinuation<Void, Never>] = []

    init(
        computerFactory: @escaping @MainActor (WindowSpaceContext) -> CurrentSpaceWindowComputer,
        onCompletion: @escaping @MainActor (WindowSpaceContext, [WindowEntry], Int) -> Void,
        generationProvider: @escaping @MainActor () -> Int = { 0 }
    ) {
        self.computerFactory = computerFactory
        self.onCompletion = onCompletion
        self.generationProvider = generationProvider
    }

    func setNotifyHandler(_ handler: (@MainActor (WindowSpaceContext) -> Void)?) {
        self.onNotify = handler
    }

    func refresh(context: WindowSpaceContext) {
        switch state {
        case .idle:
            startRefresh(context: context)
        case .refreshing(let task, let id, let generation, let taskContext):
            state = .pending(task: task, id: id, generation: generation,
                             taskContext: taskContext, nextContext: context)
        case .pending(let task, let id, let generation, let taskContext, _):
            // A newer request arrived while a follow-up was already queued.
            // Never drop it — remember the LATEST requested context so the
            // coalesced follow-up (handleCompletion) serves the most recent
            // request. The in-flight task's binding (taskContext) and its
            // dispatch-time generation are unchanged.
            state = .pending(task: task, id: id, generation: generation,
                             taskContext: taskContext, nextContext: context)
        }
    }

    private func startRefresh(context: WindowSpaceContext) {
        let computer = computerFactory(context)
        nextTaskID += 1
        let id = nextTaskID
        let generation = generationProvider()
        let task = Task.detached(priority: .userInitiated) { () -> [WindowEntry]? in
            guard !Task.isCancelled else { return nil }
            let entries = computer.compute()
            guard !Task.isCancelled else { return nil }
            return entries
        }
        state = .refreshing(task: task, id: id, generation: generation, context: context)
        observe(task, id: id)
    }

    private func observe(_ task: Task<[WindowEntry]?, Never>, id: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let entries = await task.value
            switch self.state {
            case .refreshing(_, let currentID, let generation, let context):
                // Stale callback (from a cancelled/superseded task) must not
                // corrupt the state machine.
                guard currentID == id else { return }
                if let entries {
                    self.onCompletion(context, entries, generation)
                    self.onNotify?(context)
                }
                self.handleCompletion()
            case .pending(_, let pendingID, let generation, let taskContext, let nextContext):
                // A refresh() request arrived while this task was in flight, so
                // the state moved to .pending before this callback ran. The
                // completing task is still the current one. Its entries were
                // computed for `taskContext` — the space bound when the task
                // was dispatched. If the pending request targets a different
                // space (`nextContext`, e.g. the user switched Spaces mid-flight),
                // the result no longer matches the current space: discard it and
                // let handleCompletion start the coalesced follow-up refresh for
                // `nextContext`.
                guard pendingID == id else { return }
                if taskContext == nextContext, let entries {
                    self.onCompletion(taskContext, entries, generation)
                    self.onNotify?(taskContext)
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
        case .pending(_, _, _, _, let nextContext):
            startRefresh(context: nextContext)
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
        case .refreshing(let task, _, _, _), .pending(let task, _, _, _, _):
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

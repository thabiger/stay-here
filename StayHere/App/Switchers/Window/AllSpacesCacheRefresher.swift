import Core
import Foundation

@MainActor
final class AllSpacesCacheRefresher {
    private let computerFactory: @MainActor () -> AllSpacesWindowComputer
    private let onCompletion: @MainActor ([SpaceWindowGroup]) -> Void
    private var isRefreshing = false
    private var hasPendingRefresh = false

    init(
        computerFactory: @escaping @MainActor () -> AllSpacesWindowComputer,
        onCompletion: @escaping @MainActor ([SpaceWindowGroup]) -> Void
    ) {
        self.computerFactory = computerFactory
        self.onCompletion = onCompletion
    }

    func refresh() {
        if isRefreshing {
            hasPendingRefresh = true
            return
        }
        isRefreshing = true

        let computer = computerFactory()

        DispatchQueue.global(qos: .userInitiated).async {
            let groups = computer.compute()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onCompletion(groups)
                    self.isRefreshing = false
                    if self.hasPendingRefresh {
                        self.hasPendingRefresh = false
                        self.refresh()
                    }
                }
            }
        }
    }
}

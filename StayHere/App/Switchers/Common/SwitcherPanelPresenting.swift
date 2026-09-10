import Core
import Foundation

protocol SwitcherPanelPresenting<Snapshot, Selection>: AnyObject {
    associatedtype Snapshot
    associatedtype Selection
    func presentSnapshot(_ snapshot: Snapshot, actions: SwitcherPanelActions<Selection>, updateInfo: UpdateInfo?)
    func dismissPanel()
    func releasePanel()
}

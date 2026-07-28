import Core
import Foundation

protocol SwitcherSessionDelegate<Session, Snapshot, Selection>: AnyObject {
    associatedtype Session: SwitcherSession
    associatedtype Snapshot
    associatedtype Selection where Session.Selection == Selection

    var movesSelectionOnNewSession: Bool { get }
    func provideShortcut() -> SpaceSwitcherShortcut
    func buildSession(shortcut: SpaceSwitcherShortcut, trigger: SwitcherSessionTrigger) -> Session?
    func moveSelection(in session: inout Session, offset: Int)
    func buildSnapshot(for session: Session?) -> Snapshot
    func item(at position: Int, in session: Session?) -> Selection?
    func shouldCommit(_ session: Session) -> Bool
    func commit(selection: Selection, in session: Session?) -> Bool
    func sessionDidEnd()
}

extension SwitcherSessionDelegate {
    func sessionDidEnd() {}
}

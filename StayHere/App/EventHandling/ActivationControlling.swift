import Foundation
import Activation
import Core

@MainActor
protocol ActivationControlling: AnyObject {
    func start()
    func stop()
    var eventTapClient: (any CGEventTapClient)? { get }
}

extension ActivationController: ActivationControlling {}

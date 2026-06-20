import Foundation
import Activation

@MainActor
protocol ActivationControlling: AnyObject {
    func start()
    func stop()
}

extension ActivationController: ActivationControlling {}

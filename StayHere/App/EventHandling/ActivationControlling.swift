import Foundation
import Activation
import Core

@MainActor
protocol ActivationControlling: AnyObject {
    func start(using proxy: any EventTapProxying)
    func stop(using proxy: any EventTapProxying)
}

extension ActivationController: ActivationControlling {}

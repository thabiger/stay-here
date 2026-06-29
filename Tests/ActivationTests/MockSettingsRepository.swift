import Foundation
import Core

final class MockSettingsRepository: ActivationSettings {
    var activationDockClickInterceptionEnabledStorage: Bool = true
    var activationDockClickInterceptionEnabled: Bool {
        get { activationDockClickInterceptionEnabledStorage }
        set { activationDockClickInterceptionEnabledStorage = newValue }
    }

    var activationSingleWindowAppBundleIDsStorage: [String] = SingleWindowAppBundleIDList.defaultBundleIDs
    var activationSingleWindowAppBundleIDs: [String] {
        get { activationSingleWindowAppBundleIDsStorage }
        set { activationSingleWindowAppBundleIDsStorage = newValue }
    }
}

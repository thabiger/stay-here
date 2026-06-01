import Foundation

public enum ActivationMode: String, CaseIterable, Codable {
    case replaceDockClicks
    case optionOnly
    case disabled

    public var displayName: String {
        switch self {
        case .replaceDockClicks: return "Replace Dock clicks"
        case .optionOnly: return "Only when Option is held"
        case .disabled: return "Disabled"
        }
    }
}

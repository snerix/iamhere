import Foundation

enum RefreshIntervalUnit: String, CaseIterable, Identifiable, Sendable {
    case seconds
    case minutes
    case hours

    var id: String { rawValue }

    var secondsMultiplier: Int {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3600
        }
    }

    var localizedTitle: String {
        switch self {
        case .seconds: String(localized: "Seconds")
        case .minutes: String(localized: "Minutes")
        case .hours:   String(localized: "Hours")
        }
    }
}

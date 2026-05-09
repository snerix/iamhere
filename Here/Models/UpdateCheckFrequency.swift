import Foundation

/// How often the app polls GitHub for a newer release.
///
/// Stored as a small enum even though the picker is currently hidden:
/// `.never` is the default for forked / privately signed builds, while
/// `.daily` and `.weekly` remain supported for callers or future UI that
/// explicitly opt back into GitHub release checks.
enum UpdateCheckFrequency: String, CaseIterable, Codable, Sendable, Identifiable {
    case never
    case daily
    case weekly

    var id: String { rawValue }

    /// Minimum interval between automatic checks. `nil` means automatic
    /// checks are disabled.
    var interval: TimeInterval? {
        switch self {
        case .never:  nil
        case .daily:  24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }

    var localizedTitle: String {
        switch self {
        case .never:  String(localized: "Never")
        case .daily:  String(localized: "Once a day")
        case .weekly: String(localized: "Once a week")
        }
    }
}

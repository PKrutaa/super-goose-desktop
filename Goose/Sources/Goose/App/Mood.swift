import Foundation

/// User-tunable energy level. Scales the cadence-related `Tuning` ranges so
/// the goose can be made calmer (introvert) or more present (extrovert)
/// without changing what it does — only how often.
enum Mood: String, CaseIterable, Sendable {
    case introvert
    case neutral
    case extrovert

    var displayName: String {
        switch self {
        case .introvert: return "Introvert"
        case .neutral: return "Neutral"
        case .extrovert: return "Extrovert"
        }
    }

    /// Multiplied into wait/cadence durations. >1 = quieter, <1 = louder.
    var cadenceMultiplier: Double {
        switch self {
        case .introvert: return 4.0
        case .neutral: return 1.0
        case .extrovert: return 0.5
        }
    }
}

/// UserDefaults-backed source of truth for the current mood. Stateless façade —
/// reads/writes go straight to defaults so Tuning's computed properties always
/// see the latest selection without a notification dance.
enum MoodStore {
    private static let key = "goose.mood"

    static var current: Mood {
        let raw = UserDefaults.standard.string(forKey: key) ?? Mood.neutral.rawValue
        return Mood(rawValue: raw) ?? .neutral
    }

    static func set(_ mood: Mood) {
        UserDefaults.standard.set(mood.rawValue, forKey: key)
    }
}

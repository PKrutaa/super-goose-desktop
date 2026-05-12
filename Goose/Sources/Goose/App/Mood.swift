import Foundation

/// User-tunable energy level. Scales the cadence-related `Tuning` ranges so
/// the goose can be made calmer (introvert) or more present (extrovert)
/// without changing what it does — only how often. `.disabled` is a kill
/// switch: the goose stays on screen but stops every autonomous behavior
/// (honks, agent decisions, chill, mouse-nabs, dragged windows).
enum Mood: String, CaseIterable, Sendable {
    case disabled
    case introvert
    case neutral
    case extrovert

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .introvert: return "Introvert"
        case .neutral: return "Neutral"
        case .extrovert: return "Extrovert"
        }
    }

    /// Multiplied into wait/cadence durations. >1 = quieter, <1 = louder.
    /// Unused for `.disabled` (fires are skipped entirely at their call sites).
    var cadenceMultiplier: Double {
        switch self {
        case .disabled: return 1.0
        case .introvert: return 4.0
        case .neutral: return 1.0
        case .extrovert: return 0.5
        }
    }
}

extension Notification.Name {
    /// Posted by `MoodStore.set` after the new mood is committed to defaults.
    /// Subscribers (e.g. `GooseScene`) can react — for `.disabled`, the scene
    /// resets the current task to `WanderTask` so any in-progress mouse-nab
    /// or window drag is interrupted immediately rather than running to
    /// completion.
    static let gooseMoodChanged = Notification.Name("GooseMoodChanged")
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
        NotificationCenter.default.post(name: .gooseMoodChanged, object: nil)
    }
}

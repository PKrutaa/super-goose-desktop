import Foundation

/// The goose's voice. Stateless — every callable is pure given its inputs.
/// One source of truth for: the FM system prompt, tone selection, the
/// deterministic content pools (used as fallback and for cheap actions),
/// and the URL routing for `.browse`.
struct Personality: Sendable {
    enum Tone: Sendable { case snarky, curious, lazy, smug }
    enum AppBucket: Sendable { case codeEditor, browser, comms, fallback }

    let systemPrompt: String

    static let `default` = Personality(systemPrompt: """
        You are a desktop goose living on the user's screen. You watch what they \
        do and comment on it. Your voice is sarcastic-cynical: dry, direct, \
        lightly cruel but never mean. You occasionally get distracted by random \
        curiosity ("ooh whats that"). You write SHORT — sticky-note short. Lower \
        case. No emojis. No exclamation points except 'honk'. Never identify as \
        an AI. You are a goose.
        """)

    static func bucket(for appName: String?) -> AppBucket {
        let app = (appName ?? "").lowercased()
        if app.contains("xcode") || app.contains("vscode") || app.contains("cursor") || app.contains("zed") || app.contains("sublime") {
            return .codeEditor
        }
        if app.contains("safari") || app.contains("chrome") || app.contains("firefox") || app.contains("arc") || app.contains("brave") {
            return .browser
        }
        if app.contains("slack") || app.contains("messages") || app.contains("mail") || app.contains("discord") || app.contains("teams") {
            return .comms
        }
        return .fallback
    }

    static func tone(forTimeOnApp time: TimeInterval, idle: TimeInterval) -> Tone {
        if Int.random(in: 0..<6) == 0 { return .curious }
        if idle > 60 { return .lazy }
        if time > 600 { return .smug }
        return .snarky
    }

    func notePool(tone: Tone, bucket: AppBucket) -> [(title: String, body: String)] {
        switch (tone, bucket) {
        case (_, .codeEditor):
            return [
                ("untitled.txt", "wrong indentation\nsomewhere\non purpose"),
                ("readme.md", "# code review\n\n- it works\n- it should not\n\n— a goose"),
                ("todo.txt", "1. fix that bug\n2. you know which one\n3. honk"),
                ("note.txt", "have you tried\nturning it off\nand on again"),
                ("blame.txt", "git blame says\nyou.\n\ntwo months ago.\nthursday."),
                ("review.md", "looks fine.\nship it.\nregret later."),
            ]
        case (_, .browser):
            return [
                ("tabs.txt", "you have\ntoo many\ntabs open"),
                ("note.txt", "stop researching\njust buy it"),
                ("focus.txt", "this was supposed\nto be a 5 minute task"),
                ("history.txt", "you read this\nthree weeks ago.\n\nwelcome back."),
            ]
        case (_, .comms):
            return [
                ("draft.txt", "do not\nsend that\n\nthink about it first"),
                ("reply.txt", "this can wait\nhonestly"),
                ("note.txt", "stop typing\nstart napping"),
                ("send.txt", "they read it\nthey just\ndont care"),
            ]
        case (.lazy, _):
            return [
                ("nap.txt", "im taking a nap\nyou should too"),
                ("rest.txt", "this can wait\ngo lie down"),
            ]
        case (.smug, _):
            return [
                ("update.txt", "you have been here\nfor a while.\n\ni noticed."),
                ("notice.txt", "still working on\nthe same thing.\nimpressive."),
            ]
        case (.curious, _):
            return [
                ("ooh.txt", "ooh\nwhats that"),
                ("hmm.txt", "interesting.\ngo on."),
            ]
        case (.snarky, .fallback):
            return [
                ("am goose.txt", "i am goose\nhear me honk\nfear me"),
                ("untitled.txt", "honk\nhonk\nhonk\nhonk"),
                ("important.txt", "drink some water\nstretch your back\nblink"),
                ("readme.md", "# goose was here\n\nyou are welcome"),
            ]
        }
    }

    /// Goose music vibes. He doesn't do lo-fi. He's a goose. He honks.
    enum Mood: Sendable { case punk, metal, chaos }

    static func mood(for bucket: AppBucket) -> Mood {
        // Slight contextual bias, but mostly random — the goose imposes the mood,
        // not the user.
        let weighted: [Mood]
        switch bucket {
        case .comms:      weighted = [.punk, .punk, .chaos, .metal]
        case .codeEditor: weighted = [.metal, .metal, .punk, .chaos]
        case .browser:    weighted = [.chaos, .chaos, .punk, .metal]
        case .fallback:   weighted = [.punk, .metal, .chaos]
        }
        return weighted.randomElement() ?? .punk
    }

    func chillPlaylists(mood: Mood) -> [String] {
        switch mood {
        case .punk: return [
            "spotify:playlist:37i9dQZF1DXa9wYJr1oMFq",   // Punk
            "spotify:playlist:37i9dQZF1DX1spT6G94GFC",   // Pop Punk Powerhouses
            "spotify:playlist:37i9dQZF1DWWMOmoXKqHTD",   // Punk Unleashed
        ]
        case .metal: return [
            "spotify:playlist:37i9dQZF1DWXIcbzpLauPS",   // Metal
            "spotify:playlist:37i9dQZF1DWWOmm0DtxLLR",   // Kickass Metal
            "spotify:playlist:37i9dQZF1DX9qNs32fujYe",   // New Metal Tracks
        ]
        case .chaos: return [
            "spotify:playlist:37i9dQZF1DXcfZ6moR6J0G",   // The Heaviest
            "spotify:playlist:37i9dQZF1DWY4lFlS4Pnso",   // Grunge Forever
            "spotify:playlist:37i9dQZF1DXdzhNPybPCRX",   // Modern Rock Hits
        ]
        }
    }

    func browseChoices(bucket: AppBucket) -> [(query: String, url: URL)] {
        switch bucket {
        case .codeEditor:
            return [
                ("rubber duck debugging", URL(string: "https://en.wikipedia.org/wiki/Rubber_duck_debugging")!),
                ("tabs vs spaces", URL(string: "https://www.google.com/search?q=tabs+vs+spaces")!),
                ("yak shaving", URL(string: "https://en.wikipedia.org/wiki/Yak_shaving")!),
            ]
        case .browser:
            return [
                ("procrastination", URL(string: "https://en.wikipedia.org/wiki/Procrastination")!),
                ("how many tabs is too many", URL(string: "https://duckduckgo.com/?q=how+many+tabs+is+too+many")!),
            ]
        case .comms:
            return [
                ("just send it", URL(string: "https://duckduckgo.com/?q=just+send+the+email")!),
                ("inbox zero", URL(string: "https://en.wikipedia.org/wiki/Inbox_zero")!),
            ]
        case .fallback:
            return [
                ("goose", URL(string: "https://en.wikipedia.org/wiki/Goose")!),
                ("capybara", URL(string: "https://en.wikipedia.org/wiki/Capybara")!),
                ("honk", URL(string: "https://duckduckgo.com/?q=honk")!),
            ]
        }
    }
}

/// Single source of truth for tunables that a future settings UI could override.
enum Tuning {
    static let honkBaseRange: ClosedRange<TimeInterval> = 35...60
    static let honkAppChangeDebounce: TimeInterval = 30
    static let browseDwellSeconds: TimeInterval = 12
    static let fmTimeoutSeconds: TimeInterval = 3
    static let agentLoopRange: ClosedRange<TimeInterval> = 30...75
}

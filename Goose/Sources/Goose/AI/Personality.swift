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
                ("scratch.txt", "// FIXME: everything\n// TODO: nothing\n// HONK"),
                ("commit.txt", "feat: i was here\n\nbreaks things\nfixes nothing"),
                ("rubber-duck.txt", "have you considered\ntalking to me about it\n\nim a goose"),
                ("idea.txt", "what if you\nrewrote it\nin rust"),
                ("logs.txt", "the bug is in\nthe last place you look\n(by definition)"),
                ("regret.md", "# things i shipped\n\nthis."),
                ("config.txt", "the config is wrong.\nit's always the config."),
                ("stack.txt", "did you read\nthe stacktrace\nor just panic"),
            ]
        case (_, .browser):
            return [
                ("tabs.txt", "you have\ntoo many\ntabs open"),
                ("note.txt", "stop researching\njust buy it"),
                ("focus.txt", "this was supposed\nto be a 5 minute task"),
                ("history.txt", "you read this\nthree weeks ago.\n\nwelcome back."),
                ("tabs.txt", "tab count: too many\nram: gone\nfocus: also gone"),
                ("close.txt", "close 30 tabs\nfeel powerful\nfor 4 minutes"),
                ("doom.txt", "stop scrolling\nyou are not\nreceiving information"),
                ("buy.txt", "you've been comparing\nthese for an hour\nthey are the same."),
                ("wiki.txt", "you came for one fact\nyou stayed for ten\nnone of them help"),
                ("addresses.txt", "you don't need\nanother\nstanding desk"),
            ]
        case (_, .comms):
            return [
                ("draft.txt", "do not\nsend that\n\nthink about it first"),
                ("reply.txt", "this can wait\nhonestly"),
                ("note.txt", "stop typing\nstart napping"),
                ("send.txt", "they read it\nthey just\ndont care"),
                ("inbox.txt", "inbox zero\nis a myth\nstop trying"),
                ("draft.md", "# rewrite this email\n\n- shorter\n- meaner\n- with a honk"),
                ("ping.txt", "they're not gonna\nrespond today\nlog off"),
                ("kthx.txt", "your message\nstarts with 'just'\ndon't"),
                ("react.txt", "it's a thumbs up\nnot a treaty\npick one"),
                ("calm.txt", "this is a chat\nnot a courtroom\nbreathe"),
            ]
        case (.lazy, _):
            return [
                ("nap.txt", "im taking a nap\nyou should too"),
                ("rest.txt", "this can wait\ngo lie down"),
                ("done.txt", "you've done enough\ntoday\nseriously"),
                ("blanket.txt", "the answer is\na blanket\nand a snack"),
                ("idle.txt", "the cursor is\nblinking at you\nblink back"),
                ("low.txt", "low effort hours\nopen now\nstay open"),
            ]
        case (.smug, _):
            return [
                ("update.txt", "you have been here\nfor a while.\n\ni noticed."),
                ("notice.txt", "still working on\nthe same thing.\nimpressive."),
                ("clock.txt", "an hour ago\nyou said\n'just five more minutes'"),
                ("status.txt", "status: stuck\ntime: lots\nprogress: vibes"),
                ("reminder.txt", "this is the third time\nyou've opened\nthat tab"),
                ("witness.txt", "i have been\nwatching\nthe entire time"),
            ]
        case (.curious, _):
            return [
                ("ooh.txt", "ooh\nwhats that"),
                ("hmm.txt", "interesting.\ngo on."),
                ("waddya.txt", "waddya doin\nwaddya makin\nwaddya thinkin"),
                ("look.txt", "look at this\nwait\nlook at THAT"),
                ("notes.txt", "i'm taking\nmental notes\nfor later honking"),
                ("sniff.txt", "*goose noises*\n*more goose noises*\n*judgmental*"),
            ]
        case (.snarky, .fallback):
            return [
                ("am goose.txt", "i am goose\nhear me honk\nfear me"),
                ("untitled.txt", "honk\nhonk\nhonk\nhonk"),
                ("important.txt", "drink some water\nstretch your back\nblink"),
                ("readme.md", "# goose was here\n\nyou are welcome"),
                ("posture.txt", "your spine called\nit's filing a complaint"),
                ("snack.txt", "have you eaten\ntoday\nbe honest"),
                ("vibes.txt", "low key\nhigh key\nfull goose"),
                ("legacy.txt", "what would\nthe ancients\nhonk about this"),
                ("manifesto.txt", "i was here.\ni judged.\ni honked."),
                ("warning.txt", "the goose is\ngrowing in power\nbe ready"),
            ]
        }
    }

    /// One flat list. The goose plays metal. The goose plays punk. The goose
    /// plays whatever's loud and rude. He's a goose. There is no chill option.
    struct GoosePlaylist: Sendable {
        let uri: String
        let name: String
        let vibe: String
    }

    func metalPlaylists() -> [GoosePlaylist] {
        [
            .init(uri: "spotify:playlist:37i9dQZF1DWXIcbzpLauPS", name: "Metal",                 vibe: "heavy metal staples"),
            .init(uri: "spotify:playlist:37i9dQZF1DWWOmm0DtxLLR", name: "Kickass Metal",         vibe: "uptempo kickass metal"),
            .init(uri: "spotify:playlist:37i9dQZF1DXcfZ6moR6J0G", name: "The Heaviest",          vibe: "extreme / death metal"),
            .init(uri: "spotify:playlist:37i9dQZF1DX9qNs32fujYe", name: "New Metal Tracks",      vibe: "new metal releases"),
            .init(uri: "spotify:playlist:37i9dQZF1DXa9wYJr1oMFq", name: "Punk",                  vibe: "classic punk"),
            .init(uri: "spotify:playlist:37i9dQZF1DWWMOmoXKqHTD", name: "Punk Unleashed",        vibe: "loud punk"),
            .init(uri: "spotify:playlist:37i9dQZF1DWY4lFlS4Pnso", name: "Grunge Forever",        vibe: "grunge"),
            .init(uri: "spotify:playlist:37i9dQZF1DXdxcBWuJkbcy", name: "Metalcore Mayhem",      vibe: "metalcore breakdowns"),
            .init(uri: "spotify:playlist:37i9dQZF1DX08jcQJXDnEQ", name: "Hardcore Punk",         vibe: "hardcore punk fury"),
            .init(uri: "spotify:playlist:37i9dQZF1DWWOmm0DtxLLR", name: "Thrash Metal",          vibe: "thrash riffs"),
            .init(uri: "spotify:playlist:37i9dQZF1DWXNFSTtym834", name: "Doom Metal",            vibe: "slow heavy doom"),
            .init(uri: "spotify:playlist:37i9dQZF1DX0FOF1IUWK1W", name: "All New Rock",          vibe: "loud new rock"),
            .init(uri: "spotify:playlist:37i9dQZF1DWWJOmJ7nRx0C", name: "Rock Hard",             vibe: "uncompromising rock"),
        ]
    }

    func browseChoices(bucket: AppBucket) -> [(query: String, url: URL)] {
        switch bucket {
        case .codeEditor:
            return [
                ("rubber duck debugging", URL(string: "https://en.wikipedia.org/wiki/Rubber_duck_debugging")!),
                ("tabs vs spaces", URL(string: "https://www.google.com/search?q=tabs+vs+spaces")!),
                ("yak shaving", URL(string: "https://en.wikipedia.org/wiki/Yak_shaving")!),
                ("goto considered harmful", URL(string: "https://en.wikipedia.org/wiki/Considered_harmful")!),
                ("bus factor", URL(string: "https://en.wikipedia.org/wiki/Bus_factor")!),
                ("hacker culture jargon", URL(string: "https://en.wikipedia.org/wiki/Jargon_File")!),
                ("the fiat brain bug", URL(string: "https://duckduckgo.com/?q=therac-25+software+bug")!),
                ("zalgo text", URL(string: "https://en.wikipedia.org/wiki/Zalgo_text")!),
                ("magic numbers in programming", URL(string: "https://en.wikipedia.org/wiki/Magic_number_(programming)")!),
            ]
        case .browser:
            return [
                ("procrastination", URL(string: "https://en.wikipedia.org/wiki/Procrastination")!),
                ("how many tabs is too many", URL(string: "https://duckduckgo.com/?q=how+many+tabs+is+too+many")!),
                ("information overload", URL(string: "https://en.wikipedia.org/wiki/Information_overload")!),
                ("doomscrolling", URL(string: "https://en.wikipedia.org/wiki/Doomscrolling")!),
                ("attention economy", URL(string: "https://en.wikipedia.org/wiki/Attention_economy")!),
                ("rabbit hole", URL(string: "https://en.wikipedia.org/wiki/Down_the_Rabbit_Hole")!),
                ("buyer's remorse", URL(string: "https://en.wikipedia.org/wiki/Buyer%27s_remorse")!),
            ]
        case .comms:
            return [
                ("just send it", URL(string: "https://duckduckgo.com/?q=just+send+the+email")!),
                ("inbox zero", URL(string: "https://en.wikipedia.org/wiki/Inbox_zero")!),
                ("zoom fatigue", URL(string: "https://en.wikipedia.org/wiki/Zoom_fatigue")!),
                ("email apnea", URL(string: "https://duckduckgo.com/?q=email+apnea")!),
                ("how to email like a human", URL(string: "https://duckduckgo.com/?q=how+to+write+a+short+email")!),
                ("meeting that should be email", URL(string: "https://duckduckgo.com/?q=this+meeting+could+have+been+an+email")!),
            ]
        case .fallback:
            return [
                ("goose", URL(string: "https://en.wikipedia.org/wiki/Goose")!),
                ("capybara", URL(string: "https://en.wikipedia.org/wiki/Capybara")!),
                ("honk", URL(string: "https://duckduckgo.com/?q=honk")!),
                ("untitled goose game", URL(string: "https://en.wikipedia.org/wiki/Untitled_Goose_Game")!),
                ("crows are dinosaurs", URL(string: "https://duckduckgo.com/?q=birds+are+dinosaurs")!),
                ("internet weirdness", URL(string: "https://en.wikipedia.org/wiki/Wikipedia:Unusual_articles")!),
                ("worst albums ever made", URL(string: "https://duckduckgo.com/?q=worst+albums+ever+made")!),
                ("chaos magic", URL(string: "https://en.wikipedia.org/wiki/Chaos_magic")!),
            ]
        }
    }
}

/// Single source of truth for tunables that a future settings UI could override.
enum Tuning {
    static var honkBaseRange: ClosedRange<TimeInterval> {
        let m = MoodStore.current.cadenceMultiplier
        return (35 * m) ... (60 * m)
    }
    static var honkAppChangeDebounce: TimeInterval {
        30 * MoodStore.current.cadenceMultiplier
    }
    static let browseDwellSeconds: TimeInterval = 12
    static let fmTimeoutSeconds: TimeInterval = 3
    static var agentLoopRange: ClosedRange<TimeInterval> {
        let m = MoodStore.current.cadenceMultiplier
        return (30 * m) ... (75 * m)
    }
}

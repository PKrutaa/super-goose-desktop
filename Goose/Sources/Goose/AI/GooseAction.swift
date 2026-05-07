import Foundation

/// Action types the goose can choose from. The brain returns one of these
/// (plus optional fields) and `AgentDirector` maps it to a concrete task.
///
/// `.honk` is intentionally absent: honks are owned by `HonkTicker`, which
/// fires them on its own cadence outside the agent decision loop.
enum GooseDecisionType: String, Sendable {
    case wander
    case nap
    case deepSleep
    case note
    case photo
    case browse
    case chill
}

struct GooseDecision: Sendable {
    let action: GooseDecisionType
    let noteTitle: String
    let noteBody: String
    let browseURL: URL?
    let spotifyURI: String?

    init(
        action: GooseDecisionType,
        noteTitle: String = "",
        noteBody: String = "",
        browseURL: URL? = nil,
        spotifyURI: String? = nil
    ) {
        self.action = action
        self.noteTitle = noteTitle
        self.noteBody = noteBody
        self.browseURL = browseURL
        self.spotifyURI = spotifyURI
    }
}

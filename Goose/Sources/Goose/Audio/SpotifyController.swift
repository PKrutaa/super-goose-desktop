import Foundation

/// Best-effort Spotify control via AppleScript.
///
/// No auth, no API keys — drives the user's local Spotify.app via `osascript`.
/// On any failure (Spotify not installed, permission denied, bad URI) returns
/// false; never throws. Caller is expected to proceed with the visual chill
/// regardless — the meme is the headphones, not the audio.
@MainActor
enum SpotifyController {
    private static let timeoutSeconds: TimeInterval = 3

    static func play(uri: String) async -> Bool {
        let script = "tell application \"Spotify\" to play track \"\(uri)\""
        return await runOsascript(script: script)
    }

    private static func runOsascript(script: String) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let errPipe = Pipe()
                process.standardError = errPipe
                process.standardOutput = Pipe()

                do {
                    try process.run()
                } catch {
                    FileHandle.standardError.write(Data("[Goose] SpotifyController: failed to launch osascript: \(error)\n".utf8))
                    cont.resume(returning: false)
                    return
                }

                let deadline = Date().addingTimeInterval(timeoutSeconds)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    process.terminate()
                    FileHandle.standardError.write(Data("[Goose] SpotifyController: osascript timed out\n".utf8))
                    cont.resume(returning: false)
                    return
                }

                if process.terminationStatus == 0 {
                    cont.resume(returning: true)
                } else {
                    let errData = errPipe.fileHandleForReading.availableData
                    let errStr = String(data: errData, encoding: .utf8) ?? "<unreadable>"
                    FileHandle.standardError.write(Data("[Goose] SpotifyController: osascript exit \(process.terminationStatus): \(errStr)".utf8))
                    cont.resume(returning: false)
                }
            }
        }
    }
}

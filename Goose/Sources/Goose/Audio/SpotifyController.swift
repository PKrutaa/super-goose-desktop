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
        // Capture isolated state before crossing into the global queue closure.
        let timeout = Self.timeoutSeconds
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                // Discard stdin (don't inherit a TTY — AppleScript could block
                // reading) and stdout (we don't need it). Drain stderr async
                // so the child can't deadlock when output exceeds the pipe
                // buffer (~16-64KB).
                process.standardInput = FileHandle.nullDevice
                process.standardOutput = FileHandle.nullDevice
                let errPipe = Pipe()
                process.standardError = errPipe
                let errBuffer = ErrBuffer()
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { return }
                    errBuffer.append(chunk)
                }

                do {
                    try process.run()
                } catch {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    FileHandle.standardError.write(Data("[Goose] SpotifyController: failed to launch osascript: \(error)\n".utf8))
                    cont.resume(returning: false)
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    FileHandle.standardError.write(Data("[Goose] SpotifyController: osascript timed out\n".utf8))
                    cont.resume(returning: false)
                    return
                }

                errPipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    cont.resume(returning: true)
                } else {
                    let errStr = String(data: errBuffer.read(), encoding: .utf8) ?? "<unreadable>"
                    FileHandle.standardError.write(Data("[Goose] SpotifyController: osascript exit \(process.terminationStatus): \(errStr)".utf8))
                    cont.resume(returning: false)
                }
            }
        }
    }
}

/// Lock-protected mutable Data buffer for cross-thread stderr drain.
private final class ErrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    func read() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

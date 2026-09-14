import AVFoundation

enum AudioSessionService {
    private static var hasActivated = false
    private static var lastErrorMessage: String?

    static func activate() -> String? {
        if hasActivated { return nil }
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
            hasActivated = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = errorMessage(for: error)
        }
        return lastErrorMessage
    }

    static func errorMessage(for error: any Error) -> String {
        "Coupé couldn’t activate media audio: \(error.localizedDescription)"
    }
}

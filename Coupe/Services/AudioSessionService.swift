import AVFoundation

enum AudioSessionService {
    static func activate() {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Unable to activate the playback audio session: \(error.localizedDescription)")
        }
    }
}

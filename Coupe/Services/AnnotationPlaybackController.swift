import AVFoundation

@MainActor
final class AnnotationPlaybackController {
    let player = AVPlayer()
    private var startSeconds = 0.0

    func load(url: URL, startSeconds: Double, endSeconds: Double) {
        cleanup()
        self.startSeconds = startSeconds
        let item = AVPlayerItem(url: url)
        item.forwardPlaybackEndTime = CMTime(seconds: endSeconds, preferredTimescale: 600)
        player.replaceCurrentItem(with: item)
    }

    func playSelection() {
        player.seek(to: CMTime(seconds: startSeconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func cleanup() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

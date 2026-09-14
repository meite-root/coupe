import AVKit
import Observation
import SwiftUI

@MainActor @Observable
final class PictureInPictureState {
    var isActive = false
    var isTransitioning = false
    var errorMessage: String?

    var shouldPreservePlayer: Bool { isActive || isTransitioning }
}

struct SourceVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let allowsPictureInPicture: Bool
    let state: PictureInPictureState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        configurePictureInPicture(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.delegate = context.coordinator
        configurePictureInPicture(controller)
    }

    private func configurePictureInPicture(_ controller: AVPlayerViewController) {
        controller.allowsPictureInPicturePlayback = allowsPictureInPicture
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsPictureInPicture
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private let state: PictureInPictureState

        init(state: PictureInPictureState) { self.state = state }

        func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            state.isTransitioning = true
        }

        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            state.isTransitioning = false
            state.isActive = true
        }

        func playerViewController(_ playerViewController: AVPlayerViewController,
                                  failedToStartPictureInPictureWithError error: any Error) {
            state.isTransitioning = false
            state.isActive = false
            if UIApplication.shared.applicationState == .active {
                state.errorMessage = "Picture in Picture couldn’t start: \(error.localizedDescription)"
            }
        }

        func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            state.isTransitioning = true
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            state.isTransitioning = false
            state.isActive = false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}

enum PictureInPictureEligibility {
    static func isEligible(mediaKind: MediaKind, isReady: Bool,
                           selectionState: SelectionState, systemSupported: Bool) -> Bool {
        guard mediaKind == .video, isReady, systemSupported else { return false }
        return switch selectionState {
        case .idle, .failed: true
        case .pressing, .locked, .finalizing: false
        }
    }
}

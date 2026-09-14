import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportedMedia: Sendable {
    let id: UUID, title: String, filename: String, relativePath: String
    let kind: MediaKind, duration: Double, thumbnailRelativePath: String?
}

struct MediaImportService: Sendable {
    let store: ManagedMediaStore
    func importFile(_ url: URL) async throws -> ImportedMedia {
        let id = UUID(), copied = try await store.importFile(from: url, projectID: id)
        do {
            let asset = AVURLAsset(url: copied.0)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.load(.tracks)
            guard duration.isFinite, duration > 0 else { throw ImportError.unreadableMedia }
            let kind: MediaKind = tracks.contains { $0.mediaType == .video } ? .video : .audio
            let thumbnail = kind == .video ? try? await ThumbnailService(store: store).create(for: asset, projectID: id) : nil
            return ImportedMedia(id: id, title: copied.0.deletingPathExtension().lastPathComponent,
                                 filename: copied.0.lastPathComponent, relativePath: copied.1,
                                 kind: kind, duration: duration, thumbnailRelativePath: thumbnail)
        } catch { try? store.removeProject(id: id); throw error }
    }
    enum ImportError: LocalizedError {
        case unreadableMedia
        var errorDescription: String? { "This file does not contain readable audio or video." }
    }
}

struct ThumbnailService: Sendable {
    let store: ManagedMediaStore
    func create(for asset: AVAsset, projectID: UUID) async throws -> String {
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let image = try await generator.image(at: CMTime(seconds: 0.1, preferredTimescale: 600)).image
        let relative = "Projects/\(projectID.uuidString)/thumbnail.jpg", destination = store.url(for: relative)
        try store.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: destination, options: .atomic); return relative
    }
}

struct ClipExportService: Sendable {
    let store: ManagedMediaStore
    func export(_ request: ClipExportRequest) async throws -> String {
        let source = store.url(for: request.sourceRelativePath), asset = AVURLAsset(url: source)
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = compatible.contains(AVAssetExportPresetPassthrough) ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw ExportError.unsupported }
        let ext = request.mediaKind == .video ? "mov" : "m4a"
        let type: AVFileType = request.mediaKind == .video ? .mov : .m4a
        let relative = store.clipRelativePath(projectID: request.projectID, clipID: request.clipID, extension: ext)
        let destination = store.url(for: relative)
        try store.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? store.fileManager.removeItem(at: destination)
        session.timeRange = CMTimeRange(start: CMTime(seconds: request.startSeconds, preferredTimescale: 600),
                                        end: CMTime(seconds: request.endSeconds, preferredTimescale: 600))
        do { try await session.export(to: destination, as: type); return relative }
        catch { try? store.fileManager.removeItem(at: destination); throw error }
    }
    enum ExportError: LocalizedError { case unsupported; var errorDescription: String? { "This media cannot be exported on this device." } }
}

struct ClipExportRequest: Sendable {
    let projectID: UUID
    let clipID: UUID
    let sourceRelativePath: String
    let mediaKind: MediaKind
    let startSeconds: Double
    let endSeconds: Double
}

@MainActor @Observable
final class EditorPlaybackController {
    let player = AVPlayer()
    var currentTime = 0.0
    var duration = 0.0
    var isPlaying = false
    var isReady = false
    var failureMessage: String?
    private var timeObserver: Any?

    func load(url: URL, duration: Double) {
        cleanup(); self.duration = duration
        failureMessage = AudioSessionService.activate()
        player.replaceCurrentItem(with: AVPlayerItem(url: url)); isReady = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }; self.currentTime = min(duration, max(0, time.seconds)); self.isPlaying = self.player.rate != 0
            }
        }
    }
    func toggle() { isPlaying ? player.pause() : player.play(); isPlaying.toggle() }
    func play() { player.play(); isPlaying = true }
    func seek(to seconds: Double) { player.seek(to: CMTime(seconds: SelectionMachine.clamp(seconds, duration: duration), preferredTimescale: 600)) }
    func skip(by seconds: Double) { seek(to: currentTime + seconds) }
    func cleanup() {
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        player.pause(); player.replaceCurrentItem(with: nil); isReady = false; isPlaying = false
    }
}

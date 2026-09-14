import Foundation
import SwiftData

enum MediaKind: String, Codable, CaseIterable, Sendable { case audio, video }
enum ClipExportState: String, Codable, CaseIterable, Sendable { case pending, exporting, ready, failed }

@Model
final class MediaProject {
    @Attribute(.unique) var id: UUID
    var title: String
    var importedAt: Date
    var mediaKindRaw: String
    var sourceFilename: String
    var managedSourceRelativePath: String
    var durationSeconds: Double
    var thumbnailRelativePath: String?
    @Relationship(deleteRule: .cascade, inverse: \Clip.project) var clips: [Clip]
    @Relationship(deleteRule: .cascade, inverse: \MediaAnnotation.project) var annotations: [MediaAnnotation]

    var mediaKind: MediaKind { MediaKind(rawValue: mediaKindRaw) ?? .audio }
    var sortedClips: [Clip] { clips.sorted { $0.startSeconds < $1.startSeconds } }
    var sortedAnnotations: [MediaAnnotation] {
        annotations.sorted {
            $0.startSeconds == $1.startSeconds ? $0.createdAt < $1.createdAt : $0.startSeconds < $1.startSeconds
        }
    }

    init(id: UUID = UUID(), title: String, importedAt: Date = .now, mediaKind: MediaKind,
         sourceFilename: String, managedSourceRelativePath: String, durationSeconds: Double,
         thumbnailRelativePath: String? = nil) {
        self.id = id; self.title = title; self.importedAt = importedAt
        self.mediaKindRaw = mediaKind.rawValue; self.sourceFilename = sourceFilename
        self.managedSourceRelativePath = managedSourceRelativePath
        self.durationSeconds = durationSeconds; self.thumbnailRelativePath = thumbnailRelativePath
        self.clips = []
        self.annotations = []
    }
}

@Model
final class Clip {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var startSeconds: Double
    var endSeconds: Double
    var annotationText: String
    var exportStateRaw: String
    var exportedRelativePath: String?
    var exportErrorMessage: String?
    var project: MediaProject?

    var durationSeconds: Double { max(0, endSeconds - startSeconds) }
    var exportState: ClipExportState {
        get { ClipExportState(rawValue: exportStateRaw) ?? .failed }
        set { exportStateRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, startSeconds: Double,
         endSeconds: Double, annotationText: String = "", exportState: ClipExportState = .pending,
         project: MediaProject? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt
        self.startSeconds = startSeconds; self.endSeconds = endSeconds
        self.annotationText = annotationText; self.exportStateRaw = exportState.rawValue
        self.project = project
    }
}

import Foundation
import SwiftData

@Model
final class MediaAnnotation {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var startSeconds: Double
    var endSeconds: Double
    var text: String
    var project: MediaProject?

    var durationSeconds: Double { max(0, endSeconds - startSeconds) }
    var textPreview: String { AnnotationTextPreview.make(from: text) }

    init(id: UUID = UUID(), createdAt: Date = .now, updatedAt: Date? = nil,
         startSeconds: Double, endSeconds: Double, text: String = "",
         project: MediaProject? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
        self.project = project
    }

    func updateText(_ value: String, at date: Date = .now) {
        text = value
        updatedAt = date
    }
}

enum AnnotationTextPreview {
    static let placeholder = "Add annotation…"

    static func make(from text: String, limit: Int = 160) -> String {
        let normalized = text
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return placeholder }
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

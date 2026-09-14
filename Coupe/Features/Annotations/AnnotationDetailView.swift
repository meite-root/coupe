import AVKit
import SwiftData
import SwiftUI

struct AnnotationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var annotation: MediaAnnotation
    let store: ManagedMediaStore
    @State private var playback = AnnotationPlaybackController()
    @State private var draftText: String
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var wasDeleted = false

    init(annotation: MediaAnnotation, store: ManagedMediaStore) {
        self.annotation = annotation
        self.store = store
        _draftText = State(initialValue: annotation.text)
    }

    var body: some View {
        Form {
            Section("Source") {
                LabeledContent("Project", value: annotation.project?.title ?? "Source media")
                LabeledContent("Range", value: "\(TimeFormatter.string(annotation.startSeconds)) – \(TimeFormatter.string(annotation.endSeconds))")
                LabeledContent("Duration", value: TimeFormatter.string(annotation.durationSeconds))
            }
            Section("Selection playback") {
                Button("Play Selection", systemImage: "play.fill") { playback.playSelection() }
                    .frame(minHeight: 44)
                    .accessibilityHint("Plays this range from the original source without creating a media file")
            }
            Section("Annotation") {
                TextEditor(text: $draftText)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Annotation text")
            }
            Section {
                Button("Delete Annotation", systemImage: "trash", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .accessibilityHint("Deletes only this annotation and keeps the source media and clips")
            }
        }
        .navigationTitle("Annotation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { if save() { dismiss() } }
            }
        }
        .onAppear {
            if let project = annotation.project {
                playback.load(url: store.url(for: project.managedSourceRelativePath),
                              startSeconds: annotation.startSeconds, endSeconds: annotation.endSeconds)
            }
        }
        .onDisappear {
            playback.cleanup()
            if !wasDeleted { _ = save() }
        }
        .confirmationDialog("Delete Annotation?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Annotation", role: .destructive, action: deleteAnnotation)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The source media and extracted clips will not be changed.")
        }
        .alert("Couldn’t Save Annotation", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(errorMessage ?? "Unknown error") }
    }

    @discardableResult private func save() -> Bool {
        guard draftText != annotation.text else { return true }
        let previousText = annotation.text
        let previousUpdatedAt = annotation.updatedAt
        annotation.updateText(draftText)
        do {
            try context.save()
            return true
        } catch {
            annotation.text = previousText
            annotation.updatedAt = previousUpdatedAt
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func deleteAnnotation() {
        context.delete(annotation)
        do {
            try context.save()
            wasDeleted = true
            dismiss()
        } catch {
            context.rollback()
            errorMessage = "The annotation was kept because it could not be deleted: \(error.localizedDescription)"
        }
    }
}

import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MediaProject.importedAt, order: .reverse) private var projects: [MediaProject]
    @State private var photoItem: PhotosPickerItem?
    @State private var showFiles = false
    @State private var showImportChoices = false
    @State private var isImporting = false
    @State private var pendingDeletion: MediaProject?
    @State private var errorMessage: String?
    private let store: ManagedMediaStore

    init() {
        do { store = try ManagedMediaStore() }
        catch { preconditionFailure("Application Support is unavailable: \(error.localizedDescription)") }
    }
    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty { ContentUnavailableView("No Media Yet", systemImage: "rectangle.stack.badge.plus", description: Text("Import an audio or video file to start selecting clips.")) }
                else { List(projects) { project in row(project) } }
            }
            .navigationTitle("Coupé")
            .safeAreaInset(edge: .bottom) {
                Button { showImportChoices = true } label: {
                    Label(isImporting ? "Importing…" : "Import Media", systemImage: "plus.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).controlSize(.large).padding().disabled(isImporting)
            }
            .confirmationDialog("Import Media", isPresented: $showImportChoices) {
                PhotosPicker(selection: $photoItem, matching: .videos) { Label("Choose Video from Photos", systemImage: "photo.on.rectangle") }
                Button { showFiles = true } label: { Label("Choose from Files", systemImage: "folder") }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.audio, .movie, .video, .mpeg4Movie, .quickTimeMovie]) { result in
                if case .success(let url) = result { importURL(url) }
                else if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .onChange(of: photoItem) { _, item in if let item { importPhoto(item) } }
            .alert("Import Failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "Unknown error") }
            .alert("Delete Project?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } })) {
                Button("Delete", role: .destructive) { deletePendingProject() }; Button("Cancel", role: .cancel) {}
            } message: { Text("This removes the imported source and every exported clip from Coupé.") }
        }
    }
    private func row(_ project: MediaProject) -> some View {
        NavigationLink { EditorView(project: project, store: store) } label: {
            HStack(spacing: 12) {
                MediaArtwork(project: project, store: store)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title).font(.headline).lineLimit(1)
                    Label(project.mediaKind.rawValue.capitalized, systemImage: project.mediaKind == .video ? "video" : "speaker.wave.2")
                    Text("\(TimeFormatter.string(project.durationSeconds)) • \(project.clips.count) clip\(project.clips.count == 1 ? "" : "s")")
                    Text(project.importedAt, style: .date)
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }.swipeActions { Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = project } }
    }
    private func importPhoto(_ item: PhotosPickerItem) {
        isImporting = true
        Task {
            defer { isImporting = false; photoItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw ManagedMediaError.cannotAccessFile }
                let temporary = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
                try data.write(to: temporary, options: .atomic); defer { try? FileManager.default.removeItem(at: temporary) }
                try await finishImport(temporary)
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func importURL(_ url: URL) { isImporting = true; Task { defer { isImporting = false }; do { try await finishImport(url) } catch { errorMessage = error.localizedDescription } } }
    private func finishImport(_ url: URL) async throws {
        let value = try await MediaImportService(store: store).importFile(url)
        context.insert(MediaProject(id: value.id, title: value.title, mediaKind: value.kind, sourceFilename: value.filename,
                                    managedSourceRelativePath: value.relativePath, durationSeconds: value.duration,
                                    thumbnailRelativePath: value.thumbnailRelativePath))
        try context.save()
    }
    private func deletePendingProject() {
        guard let project = pendingDeletion else { return }
        do { try store.removeProject(id: project.id); context.delete(project); try context.save() }
        catch { errorMessage = "The project record was kept because its files could not be removed: \(error.localizedDescription)" }
        pendingDeletion = nil
    }
}

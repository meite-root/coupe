import AVKit
import SwiftUI

struct ClipDetailView: View {
    @Environment(\.modelContext) private var context
    @Bindable var clip: Clip
    let store: ManagedMediaStore, retry: () -> Void
    @State private var player: AVPlayer?, shareURL: URL?

    var body: some View {
        Form {
            Section("Clip") {
                TextField("Title", text: $clip.title).onSubmit(save)
                LabeledContent("Source range", value: "\(TimeFormatter.string(clip.startSeconds)) – \(TimeFormatter.string(clip.endSeconds))")
                LabeledContent("Duration", value: TimeFormatter.string(clip.durationSeconds))
            }
            Section("Playback") {
                if clip.exportState == .ready, let player { VideoPlayer(player: player).frame(height: 220).background(.black) }
                else { ContentUnavailableView(clip.exportState.label, systemImage: clip.exportState.icon, description: Text(clip.exportErrorMessage ?? "The independent media file is not ready yet."))
                    if clip.exportState == .failed { Button("Retry Export", action: retry) } }
            }
            Section("Annotation") { TextEditor(text: $clip.annotationText).frame(minHeight: 150).onChange(of: clip.annotationText) { _, _ in save() } }
            if clip.exportState == .ready { Section { Button("Share Clip", systemImage: "square.and.arrow.up") { shareURL = exportedURL } } }
        }.navigationTitle(clip.title).navigationBarTitleDisplayMode(.inline)
            .onAppear { loadPlayer() }.onChange(of: clip.exportStateRaw) { _, _ in loadPlayer() }.onDisappear { player?.pause(); save() }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) { if let shareURL { ShareSheet(items: [shareURL]).presentationDetents([.medium, .large]) } }
    }
    private var exportedURL: URL? { clip.exportedRelativePath.map(store.url(for:)) }
    private func loadPlayer() { guard clip.exportState == .ready, let url = exportedURL else { player = nil; return }; player = AVPlayer(url: url) }
    private func save() { try? context.save() }
}

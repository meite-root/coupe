import AVKit
import SwiftData
import SwiftUI

struct EditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var project: MediaProject
    let store: ManagedMediaStore
    @State private var playback = EditorPlaybackController()
    @State private var machine = SelectionMachine()
    @State private var selectionState: SelectionState = .idle
    @State private var clipToDelete: Clip?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                preview.frame(minHeight: 210, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                playbackControls.padding(.horizontal)
                SelectionControl(state: selectionState, currentTime: playback.currentTime,
                                 begin: begin, drag: handleDrag, release: release, stop: stop).padding()
                clipsSection.padding(.horizontal)
            }.padding(.vertical)
        }.navigationTitle(project.title).navigationBarTitleDisplayMode(.inline)
            .task { playback.load(url: store.url(for: project.managedSourceRelativePath), duration: project.durationSeconds) }
            .onDisappear { interruptSelection(); playback.cleanup() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { interruptSelection() } }
            .onChange(of: playback.currentTime) { _, time in if time >= project.durationSeconds - 0.05, selectionState.startTime != nil { finalize(at: project.durationSeconds) } }
            .alert("Couldn’t Complete Action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "Unknown error") }
            .alert("Delete Clip?", isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } })) {
                Button("Delete", role: .destructive) { deleteSelectedClip() }; Button("Cancel", role: .cancel) {}
            } message: { Text("The exported clip file will be removed. The source media will not change.") }
    }
    @ViewBuilder private var preview: some View {
        if project.mediaKind == .video { VideoPlayer(player: playback.player).background(.black) }
        else { VStack(spacing: 14) { Image(systemName: "waveform.circle.fill").font(.system(size: 76)).foregroundStyle(.tint); Text(project.sourceFilename).font(.headline); Text(TimeFormatter.string(playback.currentTime)).font(.title2.monospacedDigit()) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.secondary.opacity(0.1)) }
    }
    private var playbackControls: some View {
        VStack { Slider(value: Binding(get: { playback.currentTime }, set: playback.seek), in: 0...max(0.01, project.durationSeconds)).accessibilityLabel("Playback position")
            HStack { Text(TimeFormatter.string(playback.currentTime)); Spacer(); Button { playback.toggle() } label: { Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent); Spacer(); Text(TimeFormatter.string(project.durationSeconds)) }.font(.body.monospacedDigit()) }
    }
    private var clipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clips").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
            if project.clips.isEmpty { Text("Your selected portions will appear here.").foregroundStyle(.secondary).padding(.vertical) }
            ForEach(project.sortedClips) { clip in
                NavigationLink { ClipDetailView(clip: clip, store: store, retry: { export(clip) }) } label: { ClipRow(clip: clip) }
                    .buttonStyle(.plain).contextMenu {
                        if clip.exportState == .failed { Button("Retry Export", systemImage: "arrow.clockwise") { export(clip) } }
                        Button("Delete", systemImage: "trash", role: .destructive) { clipToDelete = clip }
                    }
            }
        }
    }
    private func begin() { guard machine.begin(at: playback.currentTime, duration: project.durationSeconds, ready: playback.isReady) else { errorMessage = "Media is not ready yet."; return }; playback.play(); selectionState = machine.state; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    private func handleDrag(_ translation: CGSize, _ threshold: CGFloat) { if machine.drag(horizontal: translation.width, vertical: translation.height, threshold: threshold) { selectionState = machine.state; UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    private func release() { if case .pressing = machine.state { finalize(at: playback.currentTime) } }
    private func stop() { finalize(at: playback.currentTime) }
    private func interruptSelection() { if selectionState.startTime != nil { finalize(at: playback.currentTime) } }
    private func finalize(at end: Double) {
        let range: ClosedRange<Double>? = { if case .locked = machine.state { machine.stop(at: end, duration: project.durationSeconds) } else { machine.release(at: end, duration: project.durationSeconds) } }()
        selectionState = machine.state
        guard let range else { if case .failed(let message) = machine.state { errorMessage = message; machine.cancel(); selectionState = machine.state }; return }
        let clip = Clip(title: "Clip \(project.clips.count + 1)", startSeconds: range.lowerBound, endSeconds: range.upperBound, project: project)
        context.insert(clip); try? context.save(); machine.complete(); selectionState = machine.state; export(clip)
    }
    private func export(_ clip: Clip) { clip.exportState = .exporting; clip.exportErrorMessage = nil; try? context.save(); Task { do { clip.exportedRelativePath = try await ClipExportService(store: store).export(project: project, clip: clip); clip.exportState = .ready } catch { clip.exportState = .failed; clip.exportErrorMessage = error.localizedDescription }; try? context.save() } }
    private func deleteSelectedClip() { guard let clip = clipToDelete else { return }; do { try store.removeClip(relativePath: clip.exportedRelativePath); project.clips.removeAll { $0.id == clip.id }; context.delete(clip); try context.save() } catch { errorMessage = error.localizedDescription }; clipToDelete = nil }
}

private struct ClipRow: View {
    let clip: Clip
    var body: some View { HStack { VStack(alignment: .leading, spacing: 4) { Text(clip.title).font(.headline); Text("\(TimeFormatter.string(clip.startSeconds)) – \(TimeFormatter.string(clip.endSeconds)) • \(TimeFormatter.string(clip.durationSeconds))").font(.caption.monospacedDigit()); if !clip.annotationText.isEmpty { Text(clip.annotationText).lineLimit(1).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Label(clip.exportState.label, systemImage: clip.exportState.icon).labelStyle(.iconOnly).foregroundStyle(clip.exportState == .failed ? .red : .secondary) }.padding().background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
}

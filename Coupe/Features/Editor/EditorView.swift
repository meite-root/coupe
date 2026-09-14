import AVKit
import SwiftData
import SwiftUI

struct EditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var project: MediaProject
    let store: ManagedMediaStore
    @State private var playback = EditorPlaybackController()
    @State private var pictureInPicture = PictureInPictureState()
    @State private var suppressPictureInPictureUntilActive = false
    @State private var machine = SelectionMachine()
    @State private var selectionState: SelectionState = .idle
    @State private var mode: EditorMode = .extract
    @State private var capturedMode: EditorMode?
    @State private var clipToDelete: Clip?
    @State private var annotationToDelete: MediaAnnotation?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                preview.frame(minHeight: 210, maxHeight: 300).clipShape(RoundedRectangle(cornerRadius: 14)).padding(.horizontal)
                playbackControls.padding(.horizontal)
                modeSelector.padding(.horizontal)
                SelectionControl(state: selectionState, currentTime: playback.currentTime, mode: capturedMode ?? mode,
                                 begin: begin, drag: handleDrag, release: release, stop: stop).padding()
                editorContent.padding(.horizontal)
            }.padding(.vertical)
        }.navigationTitle(project.title).navigationBarTitleDisplayMode(.inline)
            .task {
                playback.load(url: store.url(for: project.managedSourceRelativePath), duration: project.durationSeconds)
                if let failure = playback.failureMessage { errorMessage = failure }
            }
            .onDisappear {
                interruptSelection()
                if !pictureInPicture.shouldPreservePlayer { playback.cleanup() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { suppressPictureInPictureUntilActive = false }
                else if selectionIsActive {
                    suppressPictureInPictureUntilActive = true
                    interruptSelection()
                }
            }
            .onChange(of: pictureInPicture.errorMessage) { _, message in
                if let message { errorMessage = message; pictureInPicture.errorMessage = nil }
            }
            .onChange(of: playback.currentTime) { _, time in if time >= project.durationSeconds - 0.05, selectionState.startTime != nil { finalize(at: project.durationSeconds) } }
            .alert("Couldn’t Complete Action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "Unknown error") }
            .alert("Delete Clip?", isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } })) {
                Button("Delete", role: .destructive) { deleteSelectedClip() }; Button("Cancel", role: .cancel) {}
            } message: { Text("The exported clip file will be removed. The source media will not change.") }
            .alert("Delete Annotation?", isPresented: Binding(get: { annotationToDelete != nil }, set: { if !$0 { annotationToDelete = nil } })) {
                Button("Delete", role: .destructive) { deleteSelectedAnnotation() }; Button("Cancel", role: .cancel) {}
            } message: { Text("The source media and extracted clips will not change.") }
    }
    @ViewBuilder private var preview: some View {
        if project.mediaKind == .video {
            SourceVideoPlayerView(player: playback.player, allowsPictureInPicture: pictureInPictureEligible,
                                  state: pictureInPicture).background(.black)
        }
        else { VStack(spacing: 14) { Image(systemName: "waveform.circle.fill").font(.system(size: 76)).foregroundStyle(.tint); Text(project.sourceFilename).font(.headline); Text(TimeFormatter.string(playback.currentTime)).font(.title2.monospacedDigit()) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.secondary.opacity(0.1)) }
    }
    private var playbackControls: some View {
        VStack { Slider(value: Binding(get: { playback.currentTime }, set: playback.seek), in: 0...max(0.01, project.durationSeconds)).accessibilityLabel("Playback position")
            HStack {
                Text(TimeFormatter.string(playback.currentTime))
                Spacer()
                Button { playback.skip(by: -10) } label: { Label("Back 10 seconds", systemImage: "gobackward.10").labelStyle(.iconOnly) }
                    .frame(minWidth: 44, minHeight: 44).accessibilityHint("Moves the main player backward by 10 seconds")
                Button { playback.toggle() } label: { Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") }.buttonStyle(.borderedProminent)
                Button { playback.skip(by: 10) } label: { Label("Forward 10 seconds", systemImage: "goforward.10").labelStyle(.iconOnly) }
                    .frame(minWidth: 44, minHeight: 44).accessibilityHint("Moves the main player forward by 10 seconds")
                Spacer()
                Text(TimeFormatter.string(project.durationSeconds))
            }.font(.body.monospacedDigit()) }
    }
    private var modeSelector: some View {
        Picker("Editor mode", selection: $mode) {
            ForEach(EditorMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
        }
        .pickerStyle(.segmented)
        .disabled(selectionIsActive)
        .accessibilityLabel("Editor mode")
        .accessibilityValue(mode.rawValue)
        .accessibilityHint(selectionIsActive ? "Mode cannot change during an active selection" : "Choose whether a selected range becomes an exported clip or a source annotation")
    }
    @ViewBuilder private var editorContent: some View {
        if mode == .extract { clipsSection }
        else { annotationsSection }
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
    private var annotationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Annotations").font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
            if project.annotations.isEmpty {
                Text("Hold the selection button while the portion you want to annotate plays.")
                    .foregroundStyle(.secondary).padding(.vertical)
            }
            ForEach(project.sortedAnnotations) { annotation in
                HStack(spacing: 8) {
                    Button { seekToAnnotation(annotation) } label: { AnnotationRow(annotation: annotation) }
                        .buttonStyle(.plain)
                    NavigationLink { AnnotationDetailView(annotation: annotation, store: store) } label: {
                        Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Edit annotation")
                    .accessibilityHint("Opens the annotation text editor")
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { annotationToDelete = annotation }
                }
            }
        }
    }
    private var selectionIsActive: Bool { selectionState.startTime != nil || selectionState == .finalizing }
    private var pictureInPictureEligible: Bool {
        !suppressPictureInPictureUntilActive && PictureInPictureEligibility.isEligible(
            mediaKind: project.mediaKind,
            isReady: playback.isReady,
            selectionState: selectionState,
            systemSupported: AVPictureInPictureController.isPictureInPictureSupported()
        )
    }
    private func begin() {
        guard machine.begin(at: playback.currentTime, duration: project.durationSeconds, ready: playback.isReady) else { errorMessage = "Media is not ready yet."; return }
        capturedMode = mode
        playback.play(); selectionState = machine.state; UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    private func handleDrag(_ translation: CGSize, _ threshold: CGFloat) { if machine.drag(horizontal: translation.width, vertical: translation.height, threshold: threshold) { selectionState = machine.state; UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
    private func release() { if case .pressing = machine.state { finalize(at: playback.currentTime) } }
    private func stop() { finalize(at: playback.currentTime) }
    private func interruptSelection() { if selectionState.startTime != nil { finalize(at: playback.currentTime) } }
    private func finalize(at end: Double) {
        let range: ClosedRange<Double>? = { if case .locked = machine.state { machine.stop(at: end, duration: project.durationSeconds) } else { machine.release(at: end, duration: project.durationSeconds) } }()
        selectionState = machine.state
        guard let range else {
            if case .failed(let message) = machine.state { errorMessage = message; machine.cancel(); selectionState = machine.state }
            capturedMode = nil
            return
        }
        let completion = SelectionCompletionRouter.action(for: capturedMode ?? mode, range: range)
        switch completion {
        case .createClip(let range): createClip(range: range)
        case .createAnnotation(let range): createAnnotation(range: range)
        }
        machine.complete(); selectionState = machine.state; capturedMode = nil
    }
    private func createClip(range: ClosedRange<Double>) {
        let clip = Clip(title: "Clip \(project.clips.count + 1)", startSeconds: range.lowerBound, endSeconds: range.upperBound, project: project)
        context.insert(clip)
        do { try context.save(); export(clip) }
        catch {
            context.delete(clip)
            errorMessage = "The clip could not be saved: \(error.localizedDescription)"
        }
    }
    private func createAnnotation(range: ClosedRange<Double>) {
        guard let validRange = AnnotationRange.validated(start: range.lowerBound, end: range.upperBound, duration: project.durationSeconds) else {
            errorMessage = "The selected annotation range is invalid."
            return
        }
        let annotation = MediaAnnotation(startSeconds: validRange.lowerBound, endSeconds: validRange.upperBound, project: project)
        context.insert(annotation)
        do {
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            context.delete(annotation)
            errorMessage = "The annotation could not be saved: \(error.localizedDescription)"
        }
    }
    private func export(_ clip: Clip) {
        clip.exportState = .exporting; clip.exportErrorMessage = nil; try? context.save()
        let request = ClipExportRequest(projectID: project.id, clipID: clip.id,
                                        sourceRelativePath: project.managedSourceRelativePath,
                                        mediaKind: project.mediaKind,
                                        startSeconds: clip.startSeconds, endSeconds: clip.endSeconds)
        Task {
            do {
                clip.exportedRelativePath = try await ClipExportService(store: store).export(request)
                clip.exportState = .ready
            } catch {
                clip.exportState = .failed; clip.exportErrorMessage = error.localizedDescription
            }
            try? context.save()
        }
    }
    private func seekToAnnotation(_ annotation: MediaAnnotation) {
        playback.seek(to: annotation.startSeconds)
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private func deleteSelectedClip() { guard let clip = clipToDelete else { return }; do { try store.removeClip(relativePath: clip.exportedRelativePath); project.clips.removeAll { $0.id == clip.id }; context.delete(clip); try context.save() } catch { errorMessage = error.localizedDescription }; clipToDelete = nil }
    private func deleteSelectedAnnotation() {
        guard let annotation = annotationToDelete else { return }
        context.delete(annotation)
        do { try context.save() }
        catch { context.rollback(); errorMessage = "The annotation could not be deleted: \(error.localizedDescription)" }
        annotationToDelete = nil
    }
}

private struct ClipRow: View {
    let clip: Clip
    var body: some View { HStack { VStack(alignment: .leading, spacing: 4) { Text(clip.title).font(.headline); Text("\(TimeFormatter.string(clip.startSeconds)) – \(TimeFormatter.string(clip.endSeconds)) • \(TimeFormatter.string(clip.durationSeconds))").font(.caption.monospacedDigit()); if !clip.annotationText.isEmpty { Text(clip.annotationText).lineLimit(1).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Label(clip.exportState.label, systemImage: clip.exportState.icon).labelStyle(.iconOnly).foregroundStyle(clip.exportState == .failed ? .red : .secondary) }.padding().background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
}

private struct AnnotationRow: View {
    let annotation: MediaAnnotation
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.bubble.fill").foregroundStyle(.indigo).font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(TimeFormatter.string(annotation.startSeconds)) – \(TimeFormatter.string(annotation.endSeconds)) • \(TimeFormatter.string(annotation.durationSeconds))")
                    .font(.caption.monospacedDigit())
                Text(annotation.textPreview).lineLimit(3).foregroundStyle(annotation.text.isEmpty ? .secondary : .primary)
            }
            Spacer()
            Image(systemName: "arrow.uturn.backward.circle").foregroundStyle(.secondary)
        }
        .padding().background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Annotation from \(TimeFormatter.string(annotation.startSeconds)) to \(TimeFormatter.string(annotation.endSeconds)), \(annotation.textPreview)")
        .accessibilityHint("Moves the main player to the start of this annotation")
    }
}

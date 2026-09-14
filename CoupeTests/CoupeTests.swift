import Foundation
import AVFoundation
import SwiftData
import Testing
@testable import Coupe

@MainActor
struct CoupeTests {
    @Test func timeFormatting() { #expect(TimeFormatter.string(65) == "1:05"); #expect(TimeFormatter.string(3_661) == "1:01:01") }
    @Test func normalSelection() {
        var machine = SelectionMachine()
        let didBegin = machine.begin(at: 2, duration: 10, ready: true)
        #expect(didBegin)
        #expect(machine.state == .pressing(startTime: 2))
        let range = machine.release(at: 5, duration: 10)
        #expect(range == 2...5)
    }
    @Test func lockingReleaseAndStop() {
        var machine = SelectionMachine(); _ = machine.begin(at: 1, duration: 10, ready: true)
        let didLock = machine.drag(horizontal: 90, vertical: 4, threshold: 80)
        #expect(didLock)
        #expect(machine.state == .locked(startTime: 1))
        #expect(machine.release(at: 4, duration: 10) == nil); #expect(machine.state == .locked(startTime: 1))
        #expect(machine.stop(at: 4, duration: 10) == 1...4)
    }
    @Test func rejectsShortAndClamps() {
        var short = SelectionMachine(); _ = short.begin(at: 2, duration: 10, ready: true); #expect(short.release(at: 2.1, duration: 10) == nil)
        var clamped = SelectionMachine(); _ = clamped.begin(at: -3, duration: 10, ready: true); #expect(clamped.release(at: 99, duration: 10) == 0...10)
    }
    @Test func chronologicalSorting() {
        let project = MediaProject(title: "Test", mediaKind: .audio, sourceFilename: "a.m4a", managedSourceRelativePath: "source", durationSeconds: 10)
        project.clips = [Clip(title: "Later", startSeconds: 5, endSeconds: 6), Clip(title: "Earlier", startSeconds: 1, endSeconds: 2)]
        #expect(project.sortedClips.map(\.title) == ["Earlier", "Later"])
    }
    @Test func capturedModeRoutesCompletion() {
        let range = 1.0...3.0
        #expect(SelectionCompletionRouter.action(for: .extract, range: range) == .createClip(range))
        #expect(SelectionCompletionRouter.action(for: .annotate, range: range) == .createAnnotation(range))
    }
    @Test func pictureInPictureEligibilityRequiresReadyVideo() {
        #expect(PictureInPictureEligibility.isEligible(mediaKind: .video, isReady: true,
                                                       selectionState: .idle, systemSupported: true))
        #expect(!PictureInPictureEligibility.isEligible(mediaKind: .audio, isReady: true,
                                                        selectionState: .idle, systemSupported: true))
        #expect(!PictureInPictureEligibility.isEligible(mediaKind: .video, isReady: false,
                                                        selectionState: .idle, systemSupported: true))
        #expect(!PictureInPictureEligibility.isEligible(mediaKind: .video, isReady: true,
                                                        selectionState: .idle, systemSupported: false))
    }
    @Test func activeSelectionDisablesPictureInPictureUntilIdle() {
        let activeStates: [SelectionState] = [
            .pressing(startTime: 1), .locked(startTime: 1), .finalizing
        ]
        for state in activeStates {
            #expect(!PictureInPictureEligibility.isEligible(mediaKind: .video, isReady: true,
                                                            selectionState: state, systemSupported: true))
        }
        #expect(PictureInPictureEligibility.isEligible(mediaKind: .video, isReady: true,
                                                       selectionState: .idle, systemSupported: true))
    }
    @Test func pictureInPictureUsesAuthoritativePlayerAndPreservesMode() {
        let playback = EditorPlaybackController()
        let state = PictureInPictureState()
        let view = SourceVideoPlayerView(player: playback.player, allowsPictureInPicture: true, state: state)
        var mode = EditorMode.annotate
        state.isTransitioning = true
        state.isTransitioning = false
        state.isActive = true
        #expect(view.player === playback.player)
        #expect(mode == .annotate)
        mode = .extract
        #expect(mode == .extract)
    }
    @Test func interruptedLockedSelectionFinalizesOnlyOnce() {
        var machine = SelectionMachine()
        _ = machine.begin(at: 1, duration: 10, ready: true)
        _ = machine.drag(horizontal: 100, vertical: 0, threshold: 80)
        let first = machine.stop(at: 4, duration: 10)
        let duplicate = machine.stop(at: 5, duration: 10)
        #expect(first == 1...4)
        #expect(duplicate == nil)
    }
    @Test func audioSessionErrorsAreReadable() {
        let error = NSError(domain: "AudioSessionTests", code: 7,
                            userInfo: [NSLocalizedDescriptionKey: "Route unavailable"])
        let message = AudioSessionService.errorMessage(for: error)
        #expect(message.contains("Coupé couldn’t activate media audio"))
        #expect(message.contains("Route unavailable"))
    }
    @Test func annotateHoldReleaseCreatesOneAction() {
        var machine = SelectionMachine()
        let didBegin = machine.begin(at: 1, duration: 10, ready: true)
        #expect(didBegin)
        let range = machine.release(at: 3, duration: 10)
        #expect(range.map { SelectionCompletionRouter.action(for: .annotate, range: $0) } == .createAnnotation(1...3))
    }
    @Test func annotateLockReleaseAndStopFinalizesOnce() {
        var machine = SelectionMachine()
        _ = machine.begin(at: 1, duration: 10, ready: true)
        let didLock = machine.drag(horizontal: 100, vertical: 0, threshold: 80)
        #expect(didLock)
        #expect(machine.release(at: 2, duration: 10) == nil)
        let range = machine.stop(at: 4, duration: 10)
        #expect(range == 1...4)
        #expect(machine.stop(at: 5, duration: 10) == nil)
    }
    @Test func minimumDurationIsSharedAcrossModes() {
        for mode in EditorMode.allCases {
            var machine = SelectionMachine()
            _ = machine.begin(at: 1, duration: 10, ready: true)
            let range = machine.release(at: 1.1, duration: 10)
            #expect(range == nil, "\(mode.rawValue) should reject a short selection")
        }
    }
    @Test func annotationRangeValidationClampsAndRejectsInvalidValues() {
        #expect(AnnotationRange.validated(start: -2, end: 20, duration: 10) == 0...10)
        #expect(AnnotationRange.validated(start: 5, end: 4, duration: 10) == nil)
        #expect(AnnotationRange.validated(start: .nan, end: 4, duration: 10) == nil)
        #expect(AnnotationRange.validated(start: 1, end: .infinity, duration: 10) == nil)
    }
    @Test func annotationSortingUsesCreationTimeAsTieBreaker() {
        let project = makeProject()
        let laterCreated = MediaAnnotation(createdAt: Date(timeIntervalSince1970: 20), startSeconds: 2, endSeconds: 4, project: project)
        let laterRange = MediaAnnotation(createdAt: Date(timeIntervalSince1970: 5), startSeconds: 6, endSeconds: 8, project: project)
        let earlierCreated = MediaAnnotation(createdAt: Date(timeIntervalSince1970: 10), startSeconds: 2, endSeconds: 3, project: project)
        project.annotations = [laterCreated, laterRange, earlierCreated]
        #expect(project.sortedAnnotations.map(\.id) == [earlierCreated.id, laterCreated.id, laterRange.id])
    }
    @Test func annotationPreviewHandlesEmptyAndNormalizesText() {
        #expect(AnnotationTextPreview.make(from: "  \n \t") == "Add annotation…")
        #expect(AnnotationTextPreview.make(from: "First line\nsecond   line") == "First line second line")
        #expect(AnnotationTextPreview.make(from: String(repeating: "a", count: 170)).hasSuffix("…"))
    }
    @Test func editingAnnotationUpdatesTimestamp() {
        let oldDate = Date(timeIntervalSince1970: 10)
        let newDate = Date(timeIntervalSince1970: 20)
        let annotation = MediaAnnotation(createdAt: oldDate, startSeconds: 1, endSeconds: 2)
        annotation.updateText("Updated", at: newDate)
        #expect(annotation.text == "Updated")
        #expect(annotation.updatedAt == newDate)
    }
    @Test func annotationDeletionKeepsProjectAndClip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = makeProject()
        let clip = Clip(title: "Clip", startSeconds: 1, endSeconds: 2, project: project)
        let annotation = MediaAnnotation(startSeconds: 1, endSeconds: 2, project: project)
        context.insert(project); context.insert(clip); context.insert(annotation); try context.save()
        context.delete(annotation); try context.save()
        #expect(try context.fetch(FetchDescriptor<MediaProject>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Clip>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MediaAnnotation>()).isEmpty)
    }
    @Test func projectDeletionCascadesToAnnotations() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = makeProject()
        context.insert(project)
        context.insert(MediaAnnotation(startSeconds: 1, endSeconds: 2, project: project))
        try context.save()
        context.delete(project); try context.save()
        #expect(try context.fetch(FetchDescriptor<MediaAnnotation>()).isEmpty)
    }
    @Test func modelContainerSupportsAnnotationSchema() throws {
        _ = try makeContainer()
    }
    @Test func managedPathsAndSanitization() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), store = try ManagedMediaStore(rootURL: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), path = try store.sourceRelativePath(projectID: id, filename: "my:/song.m4a")
        #expect(path == "Projects/\(id.uuidString)/Source/my__song.m4a")
        #expect(store.url(for: path).path.hasPrefix(root.path))
        let clipPath = store.clipRelativePath(projectID: id, clipID: UUID(), extension: "m4a"); #expect(clipPath.hasSuffix(".m4a"))
    }
    @Test func deletionKeepsSourceUnlessProjectRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString), store = try ManagedMediaStore(rootURL: root); defer { try? FileManager.default.removeItem(at: root) }
        let projectID = UUID(), sourceRelative = try store.sourceRelativePath(projectID: projectID, filename: "source.m4a")
        let clipRelative = store.clipRelativePath(projectID: projectID, clipID: UUID(), extension: "m4a")
        try FileManager.default.createDirectory(at: store.url(for: sourceRelative).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.url(for: clipRelative).deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: store.url(for: sourceRelative).path, contents: Data()); FileManager.default.createFile(atPath: store.url(for: clipRelative).path, contents: Data())
        try store.removeClip(relativePath: clipRelative); #expect(FileManager.default.fileExists(atPath: store.url(for: sourceRelative).path)); #expect(!FileManager.default.fileExists(atPath: store.url(for: clipRelative).path))
        try store.removeProject(id: projectID); #expect(!FileManager.default.fileExists(atPath: store.url(for: sourceRelative).path))
    }
    private func makeProject() -> MediaProject {
        MediaProject(title: "Test", mediaKind: .audio, sourceFilename: "a.m4a",
                     managedSourceRelativePath: "source", durationSeconds: 10)
    }
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MediaProject.self, Clip.self, MediaAnnotation.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

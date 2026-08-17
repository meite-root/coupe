import Foundation
import Testing
@testable import Coupe

struct CoupeTests {
    @Test func timeFormatting() { #expect(TimeFormatter.string(65) == "1:05"); #expect(TimeFormatter.string(3_661) == "1:01:01") }
    @Test func normalSelection() {
        var machine = SelectionMachine(); #expect(machine.begin(at: 2, duration: 10, ready: true))
        #expect(machine.state == .pressing(startTime: 2)); #expect(machine.release(at: 5, duration: 10) == 2...5)
    }
    @Test func lockingReleaseAndStop() {
        var machine = SelectionMachine(); _ = machine.begin(at: 1, duration: 10, ready: true)
        #expect(machine.drag(horizontal: 90, vertical: 4, threshold: 80)); #expect(machine.state == .locked(startTime: 1))
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
}

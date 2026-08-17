import Foundation

enum ManagedMediaError: LocalizedError {
    case applicationSupportUnavailable, cannotAccessFile, invalidFilename
    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable: "Coupé could not access Application Support."
        case .cannotAccessFile: "The selected file could not be accessed."
        case .invalidFilename: "The selected file has an invalid filename."
        }
    }
}

struct ManagedMediaStore: @unchecked Sendable {
    let fileManager: FileManager
    let rootURL: URL
    init(fileManager: FileManager = .default, rootURL: URL? = nil) throws {
        self.fileManager = fileManager
        if let rootURL { self.rootURL = rootURL }
        else {
            guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw ManagedMediaError.applicationSupportUnavailable
            }
            self.rootURL = support.appending(path: "Coupe", directoryHint: .isDirectory)
        }
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }
    func url(for relativePath: String) -> URL { rootURL.appending(path: relativePath) }
    func sanitizedFilename(_ filename: String) throws -> String {
        let cleaned = filename.replacingOccurrences(of: "[^A-Za-z0-9._ -]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "." else { throw ManagedMediaError.invalidFilename }
        return cleaned
    }
    func sourceRelativePath(projectID: UUID, filename: String) throws -> String {
        "Projects/\(projectID.uuidString)/Source/\(try sanitizedFilename(filename))"
    }
    func clipRelativePath(projectID: UUID, clipID: UUID, extension ext: String) -> String {
        "Projects/\(projectID.uuidString)/Clips/\(clipID.uuidString).\(ext)"
    }
    func importFile(from externalURL: URL, projectID: UUID) async throws -> (URL, String) {
        let relative = try sourceRelativePath(projectID: projectID, filename: externalURL.lastPathComponent)
        let destination = url(for: relative)
        let accessed = externalURL.startAccessingSecurityScopedResource()
        defer { if accessed { externalURL.stopAccessingSecurityScopedResource() } }
        return try await Task.detached {
            try self.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                var coordinationError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: externalURL, options: [], error: &coordinationError) { source in
                    do { try self.fileManager.copyItem(at: source, to: destination) } catch { copyError = error }
                }
                if let error = coordinationError ?? copyError as NSError? { throw error }
                return (destination, relative)
            } catch { try? self.fileManager.removeItem(at: destination); throw error }
        }.value
    }
    func removeProject(id: UUID) throws { try removeIfPresent(url(for: "Projects/\(id.uuidString)")) }
    func removeClip(relativePath: String?) throws { if let relativePath { try removeIfPresent(url(for: relativePath)) } }
    private func removeIfPresent(_ url: URL) throws { if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) } }
}

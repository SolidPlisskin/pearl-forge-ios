import Foundation

/// File operations that cooperate with iCloud Drive: reads wait for a file to
/// download, and writes, moves and deletions are announced so iCloud syncs
/// them. They block, so call them off the main thread.
enum CoordinatedFiles {
    static func read(_ url: URL) throws -> Data {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func write(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }

    /// Copies a local file (such as a new recording) into place.
    static func copyItem(at source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing,
                                       error: &coordinationError) { writeURL in
            do {
                try? FileManager.default.removeItem(at: writeURL)
                try FileManager.default.copyItem(at: source, to: writeURL)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }

    static func moveItem(at source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { from, to in
            do {
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                moveError = error
            }
        }
        if let error = coordinationError ?? moveError { throw error }
    }

    static func removeItem(at url: URL) throws {
        var coordinationError: NSError?
        var removeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { removeURL in
            do {
                try FileManager.default.removeItem(at: removeURL)
            } catch {
                removeError = error
            }
        }
        if let error = coordinationError ?? removeError { throw error }
    }

    static func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// The items in a folder, including files iCloud hasn't downloaded yet
    /// (which sit on disk as hidden ".name.icloud" stand-ins).
    static func contents(of directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var seen = Set<String>()
        return names.compactMap { name in
            var realName = name
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                realName = String(name.dropFirst().dropLast(".icloud".count))
            } else if name.hasPrefix(".") {
                return nil
            }
            guard seen.insert(realName).inserted else { return nil }
            return directory.appending(path: realName)
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// False for an iCloud file whose contents are only in the cloud right now.
    static func isDownloaded(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                             .ubiquitousItemDownloadingStatusKey]),
              values.isUbiquitousItem == true
        else { return exists(url) }
        return values.ubiquitousItemDownloadingStatus == .current
    }
}

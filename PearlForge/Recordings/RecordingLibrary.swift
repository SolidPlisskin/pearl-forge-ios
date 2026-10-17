import Foundation
import Observation
import UIKit

/// Every saved recording, wherever it lives: on this iPhone, or in a folder
/// you picked in iCloud Drive. A copy of each recording's details and texts is
/// kept on the phone so History opens instantly and works offline; audio is
/// read (and downloaded from iCloud if needed) only when you play it.
@MainActor
@Observable
final class RecordingLibrary {
    /// Newest first.
    private(set) var entries: [RecordingEntry] = []
    private(set) var isRefreshing = false
    private(set) var isMoving = false
    /// Set when the chosen folder can't be reached.
    private(set) var storageProblem: String?
    /// The step of a pearl being forged (or re-spoken) right now, per recording.
    private(set) var forging: [String: ForgeStep] = [:]
    private(set) var forgeErrors: [String: String] = [:]
    /// Recordings being sorted into topics right now.
    private(set) var sorting: Set<String> = []
    private(set) var sortErrors: [String: String] = [:]
    /// Recordings whose references are being searched for right now.
    private(set) var findingReferences: Set<String> = []
    private(set) var referenceErrors: [String: String] = [:]
    /// What the last reference search for a recording found.
    private(set) var referenceNotices: [String: String] = [:]
    /// The "Pearl Forge" folder recordings are saved in, when you chose one.
    private(set) var folderRoot: URL?

    /// The folder you picked, kept open for the life of the app.
    @ObservationIgnored private var pickedFolder: URL?

    private static let bookmarkKey = "recordingsFolderBookmark"
    private static let subfolderKey = "recordingsFolderUsesSubfolder"
    private static let folderName = "Pearl Forge"

    static var deviceRoot: URL {
        URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    private static var indexURL: URL {
        URL.applicationSupportDirectory.appending(path: "RecordingIndex.json")
    }

    init() {
        entries = Self.loadIndex()
        restoreFolder()
        Task { await refresh() }
    }

    var root: URL { folderRoot ?? Self.deviceRoot }
    var isUsingFolder: Bool { folderRoot != nil }
    var isInICloudDrive: Bool { folderRoot?.path.contains("com~apple~CloudDocs") ?? false }

    /// Where recordings are saved: "On this iPhone" or, for example,
    /// "iCloud Drive › Pearl Forge".
    var locationName: String {
        folderRoot.map(Self.displayName) ?? "On this iPhone"
    }

    func entry(_ id: String) -> RecordingEntry? {
        entries.first { $0.id == id }
    }

    // MARK: Reading

    /// Re-reads the recordings folder, picking up anything added or changed
    /// elsewhere (for example in the Files app).
    func refresh() async {
        guard !isRefreshing, !isMoving, storageProblem == nil else { return }
        let root = self.root
        if isUsingFolder && !CoordinatedFiles.exists(root) {
            storageProblem = "Pearl Forge can't find your recordings folder (\(locationName)). Choose it again in Settings."
            return
        }
        isRefreshing = true
        let cached = Dictionary(entries.map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
        let scanned = await Task.detached { Self.scan(root, cached: cached) }.value
        entries = scanned.sorted { $0.meta.created > $1.meta.created }
        saveIndex()
        isRefreshing = false
    }

    /// A recording's audio file, downloading it from iCloud first if needed.
    func audioData(_ file: String, in entryID: String) async throws -> Data {
        let url = root.appending(path: entryID).appending(path: file)
        return try await offMain { try CoordinatedFiles.read(url) }
    }

    // MARK: Saving

    /// Saves a new recording: the original audio, what you said, and its
    /// first pearl's text. The pearl's audio is added with setAudio.
    func createRecording(sourceAudio: URL, transcript: String, refinement: Refinement,
                         mode: RefinementMode, notes: String?, voiceID: String) async throws -> (RecordingEntry, Pearl) {
        let created = Date()
        let folderName = RecordingFiles.folderName(created: created, refined: refinement.text)
        let folder = root.appending(path: folderName, directoryHint: .isDirectory)
        let ext = sourceAudio.pathExtension.isEmpty ? "m4a" : sourceAudio.pathExtension
        let originalName = "original.\(ext)"
        let pearl = Pearl(id: UUID(), number: 1, created: created, mode: mode, notes: notes,
                          refinedBy: refinement.model, polisher: refinement.provider.rawValue, voiceID: voiceID,
                          textFile: Pearl.baseName(number: 1, mode: mode) + ".txt", audioFile: nil)
        let meta = RecordingMeta(title: RecordingFiles.title(for: refinement.text), created: created,
                                 originalFile: originalName, favorite: false, pearls: [pearl])
        let metaData = try RecordingFiles.encodeMeta(meta)
        try await offMain {
            try CoordinatedFiles.createDirectory(at: folder)
            try CoordinatedFiles.copyItem(at: sourceAudio, to: folder.appending(path: originalName))
            try CoordinatedFiles.write(Data(transcript.utf8),
                                       to: folder.appending(path: RecordingFiles.originalTranscriptName))
            try CoordinatedFiles.write(Data(refinement.text.utf8), to: folder.appending(path: pearl.textFile))
            try CoordinatedFiles.write(metaData, to: folder.appending(path: RecordingFiles.metaName))
        }
        let entry = RecordingEntry(folderName: folderName, meta: meta, transcript: transcript,
                                   pearlTexts: [pearl.id: refinement.text])
        replace(entry)
        return (entry, pearl)
    }

    /// Adds another pearl's text to a recording.
    func addPearl(to entryID: String, refinement: Refinement, mode: RefinementMode,
                  notes: String?, voiceID: String) async throws -> Pearl {
        guard var entry = entry(entryID) else { throw Self.missingRecording }
        let number = (entry.meta.pearls.map(\.number).max() ?? 0) + 1
        let pearl = Pearl(id: UUID(), number: number, created: Date(), mode: mode, notes: notes,
                          refinedBy: refinement.model, polisher: refinement.provider.rawValue, voiceID: voiceID,
                          textFile: Pearl.baseName(number: number, mode: mode) + ".txt", audioFile: nil)
        try await writeText(refinement.text, file: pearl.textFile, in: entryID)
        entry.meta.pearls.append(pearl)
        entry.pearlTexts[pearl.id] = refinement.text
        try await save(entry)
        return pearl
    }

    /// Saves your edits to a pearl's text.
    func updateText(_ text: String, of pearlID: UUID, in entryID: String) async throws {
        guard var entry = entry(entryID), let pearl = entry.pearl(pearlID) else { throw Self.missingRecording }
        try await writeText(text, file: pearl.textFile, in: entryID)
        entry.pearlTexts[pearlID] = text
        if pearl.number == entry.meta.pearls.map(\.number).min() {
            entry.meta.title = RecordingFiles.title(for: text)
        }
        try await save(entry)
    }

    /// Saves (or replaces) a pearl's audio.
    func setAudio(_ audio: Data, of pearlID: UUID, in entryID: String, voiceID: String) async throws {
        guard var entry = entry(entryID),
              let index = entry.meta.pearls.firstIndex(where: { $0.id == pearlID })
        else { throw Self.missingRecording }
        let pearl = entry.meta.pearls[index]
        let file = pearl.audioFile ?? Pearl.baseName(number: pearl.number, mode: pearl.mode) + ".mp3"
        let url = root.appending(path: entryID).appending(path: file)
        try await offMain { try CoordinatedFiles.write(audio, to: url) }
        entry.meta.pearls[index].audioFile = file
        entry.meta.pearls[index].voiceID = voiceID
        try await save(entry)
    }

    func setFavorite(_ favorite: Bool, for entryID: String) async {
        guard var entry = entry(entryID) else { return }
        entry.meta.favorite = favorite
        try? await save(entry)
    }

    func deletePearl(_ pearlID: UUID, from entryID: String) async throws {
        guard var entry = entry(entryID), let pearl = entry.pearl(pearlID) else { return }
        let folder = root.appending(path: entryID)
        let files = [pearl.textFile, pearl.audioFile].compactMap { $0 }
        try await offMain {
            for file in files {
                try? CoordinatedFiles.removeItem(at: folder.appending(path: file))
            }
        }
        entry.meta.pearls.removeAll { $0.id == pearlID }
        entry.pearlTexts[pearlID] = nil
        try await save(entry)
    }

    /// Deletes a recording's whole folder: the original and every pearl.
    func deleteRecording(_ entryID: String) async throws {
        let folder = root.appending(path: entryID, directoryHint: .isDirectory)
        try await offMain { try CoordinatedFiles.removeItem(at: folder) }
        entries.removeAll { $0.id == entryID }
        saveIndex()
    }

    // MARK: Forging more pearls

    /// Runs the recording's original transcript through the forge again with
    /// the given mode and request, saves the result as a new pearl, and
    /// returns it with its audio. Progress and errors are in `forging` and
    /// `forgeErrors`.
    func forgeNewPearl(for entryID: String, mode: RefinementMode, notes: String?,
                       polisher: PolisherChoice, voiceID: String) async -> (Pearl, Data)? {
        guard forging[entryID] == nil, let entry = entry(entryID) else { return nil }
        forgeErrors[entryID] = nil
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Forge a pearl")
        defer {
            forging[entryID] = nil
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        do {
            forging[entryID] = .refining
            let refinement = try await Forge.refine(entry.transcript, mode: mode, notes: notes, with: polisher)
            let pearl = try await addPearl(to: entryID, refinement: refinement, mode: mode,
                                           notes: notes, voiceID: voiceID)
            forging[entryID] = .speaking
            let audio = try await Forge.speak(refinement.text, voiceID: voiceID)
            try await setAudio(audio, of: pearl.id, in: entryID, voiceID: voiceID)
            return (self.entry(entryID)?.pearl(pearl.id) ?? pearl, audio)
        } catch {
            forgeErrors[entryID] = error.localizedDescription
            return nil
        }
    }

    /// Saves edited text for a pearl and speaks it again, replacing its audio.
    func respeak(_ pearlID: UUID, in entryID: String, text: String, voiceID: String) async -> Data? {
        guard forging[entryID] == nil else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            forgeErrors[entryID] = "There's no text to turn into speech."
            return nil
        }
        forgeErrors[entryID] = nil
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Speak a pearl")
        defer {
            forging[entryID] = nil
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        do {
            forging[entryID] = .speaking
            if entry(entryID)?.pearlTexts[pearlID] != text {
                try await updateText(text, of: pearlID, in: entryID)
            }
            let audio = try await Forge.speak(text, voiceID: voiceID)
            try await setAudio(audio, of: pearlID, in: entryID, voiceID: voiceID)
            return audio
        } catch {
            forgeErrors[entryID] = error.localizedDescription
            return nil
        }
    }

    // MARK: Topics

    /// Every topic with how many recordings are in it, biggest first.
    var topics: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries {
            for name in entry.meta.categories ?? [] { counts[name, default: 0] += 1 }
        }
        return counts.map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var topicNames: [String] { topics.map(\.name) }

    /// Recordings in a topic, oldest first, so they read as a thread.
    func entries(inTopic topic: String) -> [RecordingEntry] {
        entries.filter { $0.meta.categories?.contains(topic) == true }
            .sorted { $0.meta.created < $1.meta.created }
    }

    /// Recordings that haven't been sorted into topics yet.
    var unsorted: [RecordingEntry] {
        entries.filter { $0.meta.categories == nil }
    }

    /// Asks the AI which topics a recording belongs to. Failures are kept in
    /// `sortErrors`; the recording simply stays unsorted.
    func sortIntoTopics(_ entryID: String, with choice: PolisherChoice) async {
        guard !sorting.contains(entryID), let entry = entry(entryID) else { return }
        sorting.insert(entryID)
        sortErrors[entryID] = nil
        defer { sorting.remove(entryID) }
        do {
            let insights = try await Forge.sortIntoTopics(entry.transcript, existing: topicNames, with: choice)
            guard var current = self.entry(entryID) else { return }
            current.meta.categories = insights.categories
            if !insights.gist.isEmpty { current.meta.gist = insights.gist }
            try await save(current)
        } catch {
            sortErrors[entryID] = error.localizedDescription
        }
    }

    /// Sorts every unsorted recording, one at a time.
    func sortAllUnsorted(with choice: PolisherChoice) async {
        for entry in unsorted {
            await sortIntoTopics(entry.id, with: choice)
        }
    }

    /// Sets a recording's topics by hand.
    func setCategories(_ categories: [String], for entryID: String) async throws {
        guard var entry = entry(entryID) else { throw Self.missingRecording }
        entry.meta.categories = categories
        try await save(entry)
    }

    // MARK: References

    /// Every saved reference with the recording it was found for, newest first.
    var allReferences: [(reference: Reference, entry: RecordingEntry)] {
        entries.flatMap { entry in entry.meta.references.map { (reference: $0, entry: entry) } }
            .sorted { $0.reference.found > $1.reference.found }
    }

    /// Searches for reading related to a recording and adds what's found to
    /// its references (skipping ones it already has).
    func findReferences(for entryID: String, claudeModel: String) async {
        guard !findingReferences.contains(entryID), let entry = entry(entryID) else { return }
        findingReferences.insert(entryID)
        referenceErrors[entryID] = nil
        referenceNotices[entryID] = nil
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Find references")
        defer {
            findingReferences.remove(entryID)
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        do {
            let result = try await Forge.findReferences(for: entry, claudeModel: claudeModel)
            guard var current = self.entry(entryID) else { return }
            let known = Set(current.meta.references.compactMap { ReferenceFinder.normalize($0.url) })
            let new = result.references.filter { reference in
                ReferenceFinder.normalize(reference.url).map { !known.contains($0) } ?? false
            }
            current.meta.references.append(contentsOf: new)
            try await save(current)
            referenceNotices[entryID] = switch (new.count, result.references.count) {
            case (0, 0) where result.unverified > 0:
                "Some possible sources came up, but their links couldn't be confirmed, so nothing was saved. Try again."
            case (0, 0): "No good matches came up this time."
            case (0, _): "Nothing new: everything found was already saved."
            case (1, _): "Found 1 new reference."
            default: "Found \(new.count) new references."
            }
        } catch {
            referenceErrors[entryID] = error.localizedDescription
        }
    }

    func deleteReference(_ referenceID: UUID, from entryID: String) async {
        guard var entry = entry(entryID) else { return }
        entry.meta.references.removeAll { $0.id == referenceID }
        try? await save(entry)
    }

    // MARK: Where recordings live

    /// Saves recordings in a "Pearl Forge" folder inside the folder you picked
    /// (or in the picked folder itself if it's already called Pearl Forge),
    /// moving the recordings you already have there. Returns the names of any
    /// recordings that couldn't be moved.
    func useFolder(_ picked: URL) async throws -> [String] {
        // The app's own folder (On My iPhone › Pearl Forge) is where
        // recordings already are when no folder is chosen.
        let ownContainer = URL.documentsDirectory.deletingLastPathComponent().standardizedFileURL.path
        if picked.standardizedFileURL.path.hasPrefix(ownContainer) {
            throw PipelineError(message: "That folder is Pearl Forge's own space on this iPhone. Choose a folder in iCloud Drive instead.")
        }
        guard picked.startAccessingSecurityScopedResource() else {
            throw PipelineError(message: "Pearl Forge wasn't given access to that folder. Try choosing it again.")
        }
        let usesSubfolder = picked.lastPathComponent != Self.folderName
        let newRoot = usesSubfolder ? picked.appending(path: Self.folderName, directoryHint: .isDirectory) : picked
        let bookmark: Data
        do {
            bookmark = try picked.bookmarkData(options: .minimalBookmark,
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
            try await offMain { try CoordinatedFiles.createDirectory(at: newRoot) }
        } catch {
            picked.stopAccessingSecurityScopedResource()
            throw error
        }

        isMoving = true
        let oldRoot = root
        let names = storageProblem == nil ? entries.map(\.folderName) : []
        let unmoved: [String] = await Task.detached {
            names.filter { name in
                let from = oldRoot.appending(path: name)
                let to = newRoot.appending(path: name)
                guard from.standardizedFileURL != to.standardizedFileURL,
                      CoordinatedFiles.exists(from) else { return false }
                // Never overwrite a recording already in the new folder.
                guard !CoordinatedFiles.exists(to) else { return true }
                return (try? CoordinatedFiles.moveItem(at: from, to: to)) == nil
            }
        }.value

        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        UserDefaults.standard.set(usesSubfolder, forKey: Self.subfolderKey)
        if pickedFolder != picked {
            pickedFolder?.stopAccessingSecurityScopedResource()
        }
        pickedFolder = picked
        folderRoot = newRoot
        storageProblem = nil
        isMoving = false
        await refresh()
        return unmoved
    }

    /// Re-opens the folder you picked last time.
    private func restoreFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let picked = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                    bookmarkDataIsStale: &isStale),
              picked.startAccessingSecurityScopedResource()
        else {
            storageProblem = "Pearl Forge can't reach your recordings folder. Choose it again in Settings."
            return
        }
        if isStale, let fresh = try? picked.bookmarkData(options: .minimalBookmark,
                                                          includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        pickedFolder = picked
        folderRoot = UserDefaults.standard.bool(forKey: Self.subfolderKey)
            ? picked.appending(path: Self.folderName, directoryHint: .isDirectory)
            : picked
    }

    // MARK: Helpers

    private static let missingRecording = PipelineError(message: "That recording is no longer there.")

    private func writeText(_ text: String, file: String, in entryID: String) async throws {
        let url = root.appending(path: entryID).appending(path: file)
        try await offMain { try CoordinatedFiles.write(Data(text.utf8), to: url) }
    }

    /// Writes a recording's meta.json and updates the in-memory copy.
    private func save(_ entry: RecordingEntry) async throws {
        let url = root.appending(path: entry.folderName).appending(path: RecordingFiles.metaName)
        let data = try RecordingFiles.encodeMeta(entry.meta)
        try await offMain { try CoordinatedFiles.write(data, to: url) }
        replace(entry)
    }

    private func replace(_ entry: RecordingEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
        }
        saveIndex()
    }

    /// File work blocks while iCloud syncs, so it runs off the main thread.
    private func offMain<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await Task.detached { try work() }.value
    }

    /// Reads every recording folder, reusing the cached copy when nothing
    /// changed or when iCloud hasn't downloaded a recording's details yet.
    nonisolated private static func scan(_ root: URL, cached: [String: RecordingEntry]) -> [RecordingEntry] {
        CoordinatedFiles.contents(of: root).filter(CoordinatedFiles.isDirectory).compactMap { folder in
            let name = folder.lastPathComponent
            let previous = cached[name]
            let metaURL = folder.appending(path: RecordingFiles.metaName)
            if let previous, !CoordinatedFiles.isDownloaded(metaURL) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: metaURL)
                return previous
            }
            guard let data = try? CoordinatedFiles.read(metaURL),
                  let meta = try? RecordingFiles.decodeMeta(data)
            else { return previous }
            if let previous, previous.meta == meta { return previous }

            func text(_ file: String) -> String? {
                (try? CoordinatedFiles.read(folder.appending(path: file))).map { String(decoding: $0, as: UTF8.self) }
            }
            var texts: [UUID: String] = [:]
            for pearl in meta.pearls {
                texts[pearl.id] = text(pearl.textFile) ?? previous?.pearlTexts[pearl.id] ?? ""
            }
            return RecordingEntry(folderName: name, meta: meta,
                                  transcript: text(RecordingFiles.originalTranscriptName) ?? previous?.transcript ?? "",
                                  pearlTexts: texts)
        }
    }

    /// "iCloud Drive › Pearl Forge" or "On My iPhone › Pearl Forge".
    private static func displayName(_ folder: URL) -> String {
        let parts = folder.standardizedFileURL.pathComponents
        if let index = parts.firstIndex(of: "com~apple~CloudDocs") {
            return (["iCloud Drive"] + parts[(index + 1)...]).joined(separator: " › ")
        }
        if let index = parts.firstIndex(of: "File Provider Storage") {
            return (["On My iPhone"] + parts[(index + 1)...]).joined(separator: " › ")
        }
        return parts.suffix(2).joined(separator: " › ")
    }

    private static func loadIndex() -> [RecordingEntry] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([RecordingEntry].self, from: data)) ?? []
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? data.write(to: Self.indexURL, options: .atomic)
    }
}

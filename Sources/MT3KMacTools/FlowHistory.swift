import Foundation

struct FlowHistoryEntry: Identifiable, Codable, Equatable {
    var id: String
    var createdAt: Date
    var raw: String
    var cleaned: String
    var durationSecs: Double
    var audioPath: String?

    var createdLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

struct FlowLearnedReplacement: Identifiable, Codable, Equatable {
    var id: String { "\(from.lowercased())->\(to.lowercased())" }
    var from: String
    var to: String
}

enum FlowHistoryStore {
    static let maxEntries = 500
    static let audioRetentionDays = 14

    static func load() -> [FlowHistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL()) else { return [] }
        return (try? JSONDecoder.flow.decode([FlowHistoryEntry].self, from: data)) ?? []
    }

    static func loadAndCleanup() -> [FlowHistoryEntry] {
        var entries = load()
        entries = cleanup(entries)
        return entries
    }

    static func append(raw: String, cleaned: String, durationSecs: Double, audioPath: String?) throws -> FlowHistoryEntry {
        var entries = load()
        let entry = FlowHistoryEntry(
            id: "\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6))",
            createdAt: Date(),
            raw: raw,
            cleaned: cleaned,
            durationSecs: durationSecs,
            audioPath: audioPath
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            let overflow = entries.count - maxEntries
            let removed = Array(entries.suffix(overflow))
            entries.removeLast(overflow)
            deleteAudioFiles(for: removed)
        }
        entries = cleanup(entries)
        try save(entries)
        return entry
    }

    static func update(_ entry: FlowHistoryEntry) throws {
        var entries = load()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        try save(entries)
    }

    static func delete(_ entry: FlowHistoryEntry) throws {
        var entries = load()
        entries.removeAll { $0.id == entry.id }
        try save(entries)
        if let audioPath = entry.audioPath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }

    private static func save(_ entries: [FlowHistoryEntry]) throws {
        let url = historyURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.flow.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    private static func historyURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("history.json")
    }

    static func dictionaryURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("dictionary.json")
    }

    static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MT3K Mac Tools/Flow", isDirectory: true)
    }

    private static func cleanup(_ entries: [FlowHistoryEntry]) -> [FlowHistoryEntry] {
        let cutoff = Date().addingTimeInterval(-Double(audioRetentionDays) * 24 * 60 * 60)
        let referencedAudioPaths = Set(entries.compactMap(\.audioPath))
        deleteOrphanedAudioFiles(referencedAudioPaths: referencedAudioPaths)

        var updated = entries
        for index in updated.indices {
            guard updated[index].createdAt < cutoff,
                  let audioPath = updated[index].audioPath else { continue }
            try? FileManager.default.removeItem(atPath: audioPath)
            updated[index].audioPath = nil
        }
        return updated
    }

    private static func deleteAudioFiles(for entries: [FlowHistoryEntry]) {
        for audioPath in entries.compactMap(\.audioPath) {
            try? FileManager.default.removeItem(atPath: audioPath)
        }
    }

    private static func deleteOrphanedAudioFiles(referencedAudioPaths: Set<String>) {
        let directory = applicationSupportDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where file.pathExtension.lowercased() == "m4a" {
            if !referencedAudioPaths.contains(file.path) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

enum FlowLearnedDictionary {
    static func load() -> [FlowLearnedReplacement] {
        guard let data = try? Data(contentsOf: FlowHistoryStore.dictionaryURL()) else { return [] }
        return (try? JSONDecoder.flow.decode([FlowLearnedReplacement].self, from: data)) ?? []
    }

    static func learn(before: String, after: String) throws -> [FlowLearnedReplacement] {
        let pairs = editsToLearn(before: before, after: after)
        guard !pairs.isEmpty else { return [] }
        var replacements = load()
        for pair in pairs {
            if let index = replacements.firstIndex(where: { $0.from.caseInsensitiveCompare(pair.from) == .orderedSame }) {
                replacements[index].to = pair.to
            } else {
                replacements.append(pair)
            }
        }
        if replacements.count > 200 {
            replacements.removeFirst(replacements.count - 200)
        }
        try save(replacements)
        return pairs
    }

    static func apply(to text: String) -> String {
        var output = text
        let replacements = load().sorted { $0.from.count > $1.from.count }
        for replacement in replacements {
            guard !replacement.from.isEmpty,
                  replacement.from.caseInsensitiveCompare(replacement.to) != .orderedSame else { continue }
            output = output.replacingOccurrences(
                of: replacement.from,
                with: replacement.to,
                options: [.caseInsensitive, .diacriticInsensitive]
            )
        }
        return output
    }

    private static func save(_ replacements: [FlowLearnedReplacement]) throws {
        let url = FlowHistoryStore.dictionaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.flow.encode(replacements)
        try data.write(to: url, options: .atomic)
    }

    private static func editsToLearn(before: String, after: String) -> [FlowLearnedReplacement] {
        let beforeWords = words(before)
        let afterWords = words(after)
        guard !beforeWords.isEmpty, !afterWords.isEmpty, before != after else { return [] }

        if beforeWords.count == afterWords.count {
            return zip(beforeWords, afterWords)
                .filter { !$0.0.caseInsensitiveCompare($0.1).isSame }
                .prefix(3)
                .compactMap { candidate(from: $0.0, to: $0.1) }
        }

        let prefix = zip(beforeWords, afterWords).prefix { $0.0.caseInsensitiveCompare($0.1).isSame }.count
        let suffix = zip(beforeWords.reversed(), afterWords.reversed()).prefix { $0.0.caseInsensitiveCompare($0.1).isSame }.count
        guard prefix + suffix < beforeWords.count, prefix + suffix < afterWords.count else { return [] }

        let from = beforeWords[prefix..<(beforeWords.count - suffix)].joined(separator: " ")
        let to = afterWords[prefix..<(afterWords.count - suffix)].joined(separator: " ")
        return candidate(from: from, to: to).map { [$0] } ?? []
    }

    private static func candidate(from: String, to: String) -> FlowLearnedReplacement? {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.caseInsensitiveCompare(to) != .orderedSame else { return nil }
        guard from.count >= 3 || from.contains(" ") else { return nil }
        return FlowLearnedReplacement(from: from, to: to)
    }

    private static func words(_ text: String) -> [String] {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init)
    }
}

private extension ComparisonResult {
    var isSame: Bool { self == .orderedSame }
}

private extension JSONEncoder {
    static var flow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var flow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

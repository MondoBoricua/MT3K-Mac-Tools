import Foundation
import WhisperKit

// Local dictation engine: WhisperKit (CoreML) for transcription + an optional
// local LLM (gemma3:1b via Ollama) for text cleanup. Mirrors the DictaFlow
// pipeline (transcribe → polish) but fully native and offline.

/// Loads a WhisperKit CoreML model once and reuses it for every dictation.
/// MainActor-isolated (like FlowState) so the non-Sendable WhisperKit instance
/// never crosses an isolation boundary. WhisperKit does its heavy work on its
/// own internal executors, so awaiting it does not block the UI.
@MainActor
final class FlowLocalTranscriber {
    static let modelRepo = "argmaxinc/whisperkit-coreml"

    private var pipe: WhisperKit?
    private var loadedModel: String?
    private var loadTask: Task<Void, Error>?

    enum TranscriberError: LocalizedError {
        case empty
        case notLoaded
        var errorDescription: String? {
            switch self {
            case .empty: return "WhisperKit no devolvió texto."
            case .notLoaded: return "El modelo local no está cargado."
            }
        }
    }

    /// Ensures `model` is loaded, downloading on first use. Concurrent callers
    /// share a single in-flight load (Void result keeps it Sendable-safe).
    private func ensureLoaded(model: String) async throws {
        if pipe != nil, loadedModel == model { return }
        if let loadTask {
            try await loadTask.value
            if pipe != nil, loadedModel == model { return }
        }
        let task = Task { [weak self] in
            let repo = FlowLocalTranscriber.modelRepo
            let kit: WhisperKit
            do {
                kit = try await WhisperKit(WhisperKitConfig(model: model, modelRepo: repo, download: true))
            } catch {
                // Requested variant not in the repo → fall back to the device-recommended default
                // (model: nil) so local transcription still works instead of failing outright.
                kit = try await WhisperKit(WhisperKitConfig(modelRepo: repo, download: true))
            }
            self?.pipe = kit
            self?.loadedModel = model
        }
        loadTask = task
        defer { loadTask = nil }
        try await task.value
    }

    /// Downloads + loads the model so the first real dictation is fast.
    func preload(model: String) async throws {
        try await ensureLoaded(model: model)
    }

    /// Detected language from the last Auto transcription (for UI feedback), e.g. "es"/"en".
    private(set) var lastDetectedLanguage: String?

    func transcribe(audioPath: String, model: String, language: String?, translate: Bool) async throws -> String {
        try await ensureLoaded(model: model)
        guard let pipe else { throw TranscriberError.notLoaded }
        // WhisperKit is non-Sendable but its async methods are internally safe; only one
        // dictation runs at a time (the prior transcriptionTask is cancelled on a new one).
        nonisolated(unsafe) let kit = pipe

        // Auto mode: run WhisperKit's DEDICATED language detector first, then transcribe with
        // that language pinned. The in-decode detectLanguage flag was unreliable and kept
        // defaulting to English; a dedicated detection pass + pinned language is solid.
        var resolvedLanguage = language
        if language == nil, !translate {
            if let detected = try? await kit.detectLanguage(audioPath: audioPath) {
                resolvedLanguage = detected.language
                lastDetectedLanguage = detected.language
            }
        }

        let options = DecodingOptions(
            task: translate ? .translate : .transcribe,
            language: resolvedLanguage,
            usePrefillPrompt: resolvedLanguage != nil,
            detectLanguage: resolvedLanguage == nil
        )
        let results: [TranscriptionResult] = try await kit.transcribe(audioPath: audioPath, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriberError.empty }
        return text
    }
}

/// Polishes raw transcription with a local LLM (default gemma3:1b via Ollama).
/// Faithful port of DictaFlow's literal-editor prompt + preamble stripping.
enum FlowTextCleaner {
    static let defaultModel = "gemma3:1b"
    private static let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")!

    private static let promptHeader = """
    You are a literal text editor. Fix only obvious typos, missing punctuation, missing capitalization, and short transcription fragments where a partial word appears immediately before its full form (e.g., "dict dictating" → "dictating", "s sentence" → "sentence"). Do NOT change real words. Do NOT rephrase. Leave legitimate adjacent words alone (e.g., "in inside", "my myself", "a apple"). Output ONLY the fixed text.

    Input: i went to the store and bought some apples
    Output: I went to the store and bought some apples.

    Input: she said hi and then walked away
    Output: She said hi and then walked away.

    Input: i am dict dictating a s sentence
    Output: I am dictating a sentence.

    Input: we went in inside the house
    Output: We went in inside the house.


    """

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
        let options: Options
        struct Options: Encodable {
            let temperature: Double
            // swiftlint:disable:next identifier_name
            let num_predict: Int
        }
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    private static func buildPrompt(_ input: String) -> String {
        "\(promptHeader)Input: \(input)\nOutput:"
    }

    private static func numPredict(_ input: String) -> Int {
        max(60, input.split(whereSeparator: \.isWhitespace).count * 2)
    }

    /// Returns the polished text, or `nil` if the LLM is unreachable/errors
    /// (caller should fall back to the raw text).
    static func clean(_ raw: String, model: String) async -> String? {
        let body = GenerateRequest(
            model: model,
            prompt: buildPrompt(raw),
            stream: false,
            options: .init(temperature: 0, num_predict: numPredict(raw))
        )
        guard let httpBody = try? JSONEncoder().encode(body) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            let cleaned = stripPreamble(decoded.response)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    private static let colonTailPreambles = ["Here is the", "Here's the", "Here is", "Here's", "Sure,"]
    private static let fullPreambles = ["Output:", "Cleaned:"]

    /// Strips chatty LLM preambles like `Here's the cleaned text:` or `Output:`.
    static func stripPreamble(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        for preamble in colonTailPreambles where text.lowercased().hasPrefix(preamble.lowercased()) {
            let after = text.dropFirst(preamble.count)
            if let colonIdx = after.firstIndex(of: ":") {
                let head = after[after.startIndex..<colonIdx]
                if head.count <= 20 {
                    text = String(after[after.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }

        for preamble in fullPreambles where text.lowercased().hasPrefix(preamble.lowercased()) {
            text = String(text.dropFirst(preamble.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        if text.hasPrefix("\"") {
            text.removeFirst()
            if text.hasSuffix("\"") { text.removeLast() }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

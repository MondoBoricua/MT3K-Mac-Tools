// MT3K Flow — FlowState: estado, grabación, transcripción y paste.
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import Security
import SwiftUI

@MainActor
final class FlowState: ObservableObject {
    @Published var micPermission: FlowPermissionState = .unknown
    @Published var accessibilityPermission: FlowPermissionState = .unknown
    @Published var inputMonitoringPermission: FlowPermissionState = .unknown
    @Published var isRecording = false
    @Published var micLevel: Double = 0
    @Published var lastClipPath = ""
    @Published var lastClipDuration = "Sin pruebas"
    @Published var status = "Flow listo para configurar."
    @Published var localModelStatus = "Modelo local opcional. Cloud no descarga modelos."
    @Published var providerStatus = "Provider local seleccionado."
    @Published var groqKeySaved = false
    @Published var openAIKeySaved = false
    @Published var currentHotkey: FlowHotkey = .load()
    @Published var hotkeyStatus = "Flow apagado. Actívalo para registrar el hotkey."
    @Published var history: [FlowHistoryEntry] = []
    @Published var learnedReplacements: [FlowLearnedReplacement] = []
    @Published var historyStatus = "History listo para aprender correcciones."
    @Published var activeProvider: FlowProvider = .local
    @Published var activeCloudModel = ""
    @Published var activeLanguage: FlowLanguage = .automatic
    @Published var cleanupEnabled = true
    @Published var cleanupModel = FlowTextCleaner.defaultModel
    @Published var localModelLoading = false
    @Published var localModelReady = false

    // WhisperKit CoreML model variant for local transcription (resolved within argmaxinc/whisperkit-coreml).
    // Note the underscore: the repo folders are openai_whisper-large-v3_turbo (hyphen form 404s).
    let localModelVariant = "large-v3_turbo"
    private let localTranscriber = FlowLocalTranscriber()

    private var whisperLanguageCode: String? {
        switch activeLanguage {
        case .spanish: return "es"
        case .english: return "en"
        case .automatic, .translateEnglish: return nil
        }
    }

    private let hotkeyManager = FlowHotkeyManager()
    private let cursorHUD = FlowCursorHUDController()
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?
    private var hotkeyPressAt: Date?
    private var ignoreHotkeyRelease = false
    private var pasteTargetPID: pid_t?
    private var bootstrapped = false

    var permissionsReady: Bool {
        micPermission.ok && accessibilityPermission.ok && inputMonitoringPermission.ok
    }

    func bootstrapFromUserDefaults(force: Bool = false) {
        guard force || !bootstrapped else { return }
        bootstrapped = true

        let defaults = UserDefaults.standard
        let provider = FlowProvider(rawValue: defaults.string(forKey: "flowProvider") ?? "") ?? .local
        let language = FlowLanguage(rawValue: defaults.string(forKey: "flowLanguage") ?? "") ?? .automatic
        let model = provider == .groq
            ? defaults.string(forKey: "flowGroqModel") ?? "whisper-large-v3"
            : defaults.string(forKey: "flowOpenAIModel") ?? "gpt-4o-transcribe"

        cleanupEnabled = defaults.object(forKey: "flowCleanupEnabled") as? Bool ?? true
        configureTranscription(provider: provider, model: model, language: language)
        refreshPermissions()
        refreshSecrets()
        loadHistory()
        applyProvider(provider)
        setFlowActive(defaults.bool(forKey: "flowMenuBarEnabled"))
    }

    func refreshSecrets() {
        groqKeySaved = FlowSecrets.hasAPIKey(for: .groq)
        openAIKeySaved = FlowSecrets.hasAPIKey(for: .openAI)
    }

    func loadHistory() {
        history = FlowHistoryStore.loadAndCleanup()
        learnedReplacements = FlowLearnedDictionary.load()
    }

    func configureTranscription(provider: FlowProvider, model: String, language: FlowLanguage) {
        activeProvider = provider
        activeCloudModel = model
        activeLanguage = language
    }

    /// gemma3:1b (or configured model) polish via Ollama, then the user's learned replacements.
    /// LLM cleanup is best-effort: on any failure it falls back to the raw text + dictionary.
    private func cleanupTranscription(_ raw: String) async -> String {
        var text = raw
        if cleanupEnabled, let polished = await FlowTextCleaner.clean(raw, model: cleanupModel) {
            text = polished
        }
        return FlowLearnedDictionary.apply(to: text)
    }

    func preloadLocalModel() async {
        guard !localModelLoading else { return }
        localModelLoading = true
        localModelStatus = "Descargando/cargando \(localModelVariant) (WhisperKit, ~1.5 GB la primera vez)…"
        defer { localModelLoading = false }
        do {
            try await localTranscriber.preload(model: localModelVariant)
            localModelReady = true
            localModelStatus = "Modelo local \(localModelVariant) listo."
        } catch {
            localModelReady = false
            localModelStatus = "No se pudo cargar el modelo local: \(error.localizedDescription)"
        }
    }

    private func transcribeLocalRecording(audioPath: String, duration: Double, targetPID: pid_t?) async {
        if !localModelReady {
            status = "Cargando modelo local \(localModelVariant)… La primera vez compila para el Neural Engine y puede tardar varios minutos (no está congelado)."
            cursorHUD.update(level: 0, mode: .processing)
        }
        do {
            let text = try await localTranscriber.transcribe(
                audioPath: audioPath,
                model: localModelVariant,
                language: whisperLanguageCode,
                translate: activeLanguage == .translateEnglish
            )
            localModelReady = true
            guard !Task.isCancelled else { return }
            let cleaned = await cleanupTranscription(text)
            guard !Task.isCancelled else { return }
            appendHistory(raw: text, cleaned: cleaned, durationSecs: duration, audioPath: audioPath)
            paste(cleaned, targetPID: targetPID)
            let detected = (activeLanguage == .automatic) ? " · detectó: \(localTranscriber.lastDetectedLanguage ?? "?")" : ""
            status = "Dictado pegado (local)\(detected)."
            cursorHUD.hide()
        } catch {
            if Task.isCancelled { return }
            status = "Falló transcripción local: \(error.localizedDescription)"
            cursorHUD.hide()
            appendHistory(raw: "Error: \(error.localizedDescription)", cleaned: "Error: \(error.localizedDescription)", durationSecs: duration, audioPath: audioPath)
        }
    }

    func setFlowActive(_ active: Bool) {
        if active {
            registerCurrentHotkey()
        } else {
            hotkeyManager.deactivate()
            hotkeyStatus = "Flow apagado."
            cursorHUD.hide()
            if isRecording {
                stopMicTest()
            }
        }
    }

    func updateHotkey(_ hotkey: FlowHotkey, flowActive: Bool) {
        currentHotkey = hotkey
        hotkey.save()
        hotkeyStatus = "Hotkey cambiado a \(hotkey.display)."
        if flowActive {
            registerCurrentHotkey()
        }
    }

    func registerCurrentHotkey() {
        hotkeyManager.onPress = { [weak self] in self?.handleHotkeyPress() }
        hotkeyManager.onRelease = { [weak self] in self?.handleHotkeyRelease() }
        do {
            try hotkeyManager.activate(currentHotkey)
            hotkeyStatus = "Hotkey activo: \(currentHotkey.display). Mantén para grabar; toque corto queda en toggle."
        } catch {
            hotkeyStatus = error.localizedDescription
        }
    }

    func refreshPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermission = .granted
        case .denied, .restricted:
            micPermission = .denied
        case .notDetermined:
            micPermission = .prompt
        @unknown default:
            micPermission = .unknown
        }

        accessibilityPermission = AXIsProcessTrusted() ? .granted : .prompt

        let inputStatus = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch inputStatus {
        case kIOHIDAccessTypeGranted:
            inputMonitoringPermission = .granted
        case kIOHIDAccessTypeDenied:
            inputMonitoringPermission = .denied
        default:
            inputMonitoringPermission = .prompt
        }
    }

    func requestMicrophone() async {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch currentStatus {
        case .authorized:
            micPermission = .granted
            status = "Micrófono autorizado."
        case .notDetermined:
            await promptForMicrophone()
        case .denied, .restricted:
            status = "Reiniciando permiso de micrófono para pedirlo de nuevo..."
            micPermission = .prompt
            _ = await resetTCCPermission(service: "Microphone")
            try? await Task.sleep(nanoseconds: 350_000_000)
            await promptForMicrophone()
        @unknown default:
            micPermission = .unknown
            status = "No pude leer el estado del micrófono."
        }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        accessibilityPermission = granted ? .granted : .prompt
        status = granted ? "Accessibility autorizado." : "Autoriza MT3K Mac Tools en Privacy & Security."
    }

    func requestInputMonitoring() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermissions()
        status = "Revisa Input Monitoring en System Settings."
    }

    private func promptForMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        micPermission = granted ? .granted : .denied
        status = granted ? "Micrófono autorizado." : "Permiso de micrófono denegado."
        refreshPermissions()
        if !granted {
            openPrivacyPane(.microphone)
        }
    }

    private func resetTCCPermission(service: String) async -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mt3k.mac-tools"
        // Run tccutil off the main actor so waitUntilExit never blocks the UI run loop.
        let result: Result<Int32, Error> = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            do {
                try process.run()
                process.waitUntilExit()
                return .success(process.terminationStatus)
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let code):
            return code == 0
        case .failure(let error):
            status = "No pude reiniciar TCC: \(error.localizedDescription)"
            return false
        }
    }

    func toggleMicTest() {
        isRecording ? stopMicTest() : startMicTest()
    }

    private func handleHotkeyPress() {
        if isRecording {
            ignoreHotkeyRelease = true
            stopMicTest()
            status = "Grabación detenida por hotkey."
            return
        }

        hotkeyPressAt = Date()
        ignoreHotkeyRelease = false
        startMicTest()
    }

    private func handleHotkeyRelease() {
        guard isRecording else { return }
        if ignoreHotkeyRelease {
            ignoreHotkeyRelease = false
            return
        }

        guard let hotkeyPressAt else { return }
        let elapsed = Date().timeIntervalSince(hotkeyPressAt)
        if elapsed < 0.25 {
            status = "Toque corto: Flow sigue grabando. Toca \(currentHotkey.display) otra vez para detener."
            return
        }

        stopMicTest()
        status = "Grabación detenida al soltar hotkey."
    }

    func startMicTest() {
        refreshPermissions()
        guard micPermission.ok else {
            status = "Autoriza el micrófono antes de probar Flow."
            return
        }

        // A new dictation supersedes any transcription still in flight.
        transcriptionTask?.cancel()

        pasteTargetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let url = Self.applicationSupportDirectory()
            .appendingPathComponent("flow-mic-test-\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder
            startedAt = Date()
            isRecording = true
            lastClipPath = url.path
            status = "Grabando dictado..."
            cursorHUD.show(level: 0, mode: .recording)
            startMeterTimer()
        } catch {
            status = "No pude iniciar grabación: \(error.localizedDescription)"
            isRecording = false
            recorder = nil
        }
    }

    func stopMicTest() {
        guard isRecording else { return }
        recorder?.stop()
        meterTimer?.invalidate()
        meterTimer = nil
        micLevel = 0
        isRecording = false
        cursorHUD.update(level: 0, mode: .processing)
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        lastClipDuration = String(format: "%.1f s", duration)
        let audioPath = lastClipPath
        let targetPID = pasteTargetPID
        pasteTargetPID = nil

        transcriptionTask?.cancel()
        if activeProvider == .local {
            status = localModelReady
                ? "Transcribiendo local con WhisperKit..."
                : "Preparando modelo local (primera vez compila, puede tardar)…"
            transcriptionTask = Task {
                await transcribeLocalRecording(audioPath: audioPath, duration: duration, targetPID: targetPID)
            }
        } else {
            status = "Transcribiendo con \(activeProvider.rawValue)..."
            transcriptionTask = Task {
                await transcribeCloudRecording(audioPath: audioPath, duration: duration, targetPID: targetPID)
            }
        }
    }

    private func transcribeCloudRecording(audioPath: String, duration: Double, targetPID: pid_t?) async {
        do {
            let text = try await cloudTranscription(audioPath: audioPath)
            // Superseded by a newer dictation: stay silent, don't paste or log.
            guard !Task.isCancelled else { return }
            let cleaned = await cleanupTranscription(text)
            guard !Task.isCancelled else { return }
            appendHistory(raw: text, cleaned: cleaned, durationSecs: duration, audioPath: audioPath)
            paste(cleaned, targetPID: targetPID)
            status = "Dictado pegado con \(activeProvider.rawValue)."
            cursorHUD.hide()
        } catch {
            // A cancelled in-flight request (URLError.cancelled / CancellationError) is not a failure.
            if Task.isCancelled { return }
            status = "Falló transcripción \(activeProvider.rawValue): \(error.localizedDescription)"
            cursorHUD.hide()
            appendHistory(raw: "Error: \(error.localizedDescription)", cleaned: "Error: \(error.localizedDescription)", durationSecs: duration, audioPath: audioPath)
        }
    }

    private func cloudTranscription(audioPath: String) async throws -> String {
        guard let key = FlowSecrets.apiKey(for: activeProvider), !key.isEmpty else {
            throw NSError(domain: "MT3KFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta API key de \(activeProvider.rawValue). Pégala y guárdala en Provider cloud."])
        }

        let audioURL = URL(fileURLWithPath: audioPath)
        // Read the recording off the main actor; multi-MB files would otherwise freeze the UI.
        let audioData = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: audioURL)
        }.value
        let boundary = "MT3KFlowBoundary\(UUID().uuidString)"
        let endpoint = cloudEndpoint()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, audioData: audioData)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw NSError(domain: "MT3KFlow", code: statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }
        let decoded = try JSONDecoder().decode(FlowTranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NSError(domain: "MT3KFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transcripción vacía."])
        }
        return text
    }

    private func cloudEndpoint() -> URL {
        let suffix = activeLanguage == .translateEnglish ? "translations" : "transcriptions"
        switch activeProvider {
        case .groq:
            return URL(string: "https://api.groq.com/openai/v1/audio/\(suffix)")!
        case .openAI:
            return URL(string: "https://api.openai.com/v1/audio/\(suffix)")!
        case .local:
            return URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        }
    }

    private func multipartBody(boundary: String, audioData: Data) -> Data {
        var body = Data()
        body.appendMultipartField("model", value: activeCloudModel.isEmpty ? defaultCloudModel : activeCloudModel, boundary: boundary)
        body.appendMultipartField("response_format", value: "json", boundary: boundary)
        body.appendMultipartField("temperature", value: "0", boundary: boundary)
        if activeLanguage == .spanish {
            body.appendMultipartField("language", value: "es", boundary: boundary)
        } else if activeLanguage == .english {
            body.appendMultipartField("language", value: "en", boundary: boundary)
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.m4a\"\r\n")
        body.append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private var defaultCloudModel: String {
        activeProvider == .groq ? "whisper-large-v3" : "gpt-4o-transcribe"
    }

    private var pasteRestoreTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?

    private func paste(_ text: String, targetPID: pid_t?) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        if let targetPID {
            keyDown?.postToPid(targetPID)
            keyUp?.postToPid(targetPID)
        } else {
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }

        if let previous {
            // Cancel any pending restore so a rapid second dictation isn't clobbered
            // by the previous invocation's delayed clipboard restore.
            pasteRestoreTask?.cancel()
            pasteRestoreTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }

    func appendHistory(raw: String, cleaned: String, durationSecs: Double, audioPath: String?) {
        do {
            _ = try FlowHistoryStore.append(raw: raw, cleaned: cleaned, durationSecs: durationSecs, audioPath: audioPath)
            loadHistory()
            historyStatus = "Entrada añadida al history."
        } catch {
            historyStatus = "No pude guardar history: \(error.localizedDescription)"
        }
    }

    func updateHistoryCorrection(_ entry: FlowHistoryEntry, cleaned: String) {
        var updated = entry
        updated.cleaned = cleaned
        do {
            try FlowHistoryStore.update(updated)
            let learned = try FlowLearnedDictionary.learn(before: entry.cleaned, after: cleaned)
            loadHistory()
            if learned.isEmpty {
                historyStatus = "Corrección guardada. No había pares claros para aprender."
            } else {
                let label = learned.map { "\($0.from) → \($0.to)" }.joined(separator: ", ")
                historyStatus = "Corrección guardada y aprendida: \(label)"
            }
        } catch {
            historyStatus = "No pude guardar corrección: \(error.localizedDescription)"
        }
    }

    func deleteHistoryEntry(_ entry: FlowHistoryEntry) {
        do {
            try FlowHistoryStore.delete(entry)
            loadHistory()
            historyStatus = "Entrada eliminada."
        } catch {
            historyStatus = "No pude eliminar entrada: \(error.localizedDescription)"
        }
    }

    func revealLastClip() {
        guard !lastClipPath.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastClipPath)])
    }

    func openPrivacyPane(_ pane: FlowPrivacyPane) {
        guard let url = URL(string: pane.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func openHuggingFaceModel(_ modelID: String) {
        guard let url = URL(string: "https://huggingface.co/\(modelID)") else { return }
        NSWorkspace.shared.open(url)
    }

    func applyProvider(_ provider: FlowProvider) {
        refreshSecrets()
        switch provider {
        case .local:
            status = "Provider local seleccionado."
            providerStatus = "Local: WhisperKit (CoreML) transcribe y gemma3:1b limpia el texto. 100% offline."
            localModelStatus = "Preparando modelo local \(localModelVariant)… (la primera vez descarga ~1.5 GB)"
            Task { await preloadLocalModel() }
        case .groq:
            status = "Provider Groq seleccionado."
            providerStatus = "Groq usa transcripción cloud compatible OpenAI. No descarga modelo local."
            localModelStatus = "Cloud Groq no necesita modelo local."
        case .openAI:
            status = "Provider OpenAI seleccionado."
            providerStatus = "OpenAI usa audio/transcriptions en cloud. No descarga modelo local."
            localModelStatus = "Cloud OpenAI no necesita modelo local."
        }
    }

    func openProviderConsole(_ provider: FlowProvider) {
        let urlString: String
        switch provider {
        case .local:
            urlString = "https://huggingface.co/argmaxinc/whisperkit-coreml"
        case .groq:
            urlString = "https://console.groq.com/keys"
        case .openAI:
            urlString = "https://platform.openai.com/api-keys"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func saveAPIKey(_ key: String, for provider: FlowProvider) {
        guard provider != .local else { return }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            providerStatus = "Pega una API key antes de guardar."
            return
        }

        do {
            try FlowSecrets.saveAPIKey(trimmed, for: provider)
            refreshSecrets()
            providerStatus = "\(provider.rawValue) API key guardada en Keychain."
        } catch {
            providerStatus = "No pude guardar la API key: \(error.localizedDescription)"
        }
    }

    func deleteAPIKey(for provider: FlowProvider) {
        guard provider != .local else { return }
        do {
            try FlowSecrets.deleteAPIKey(for: provider)
            refreshSecrets()
            providerStatus = "\(provider.rawValue) API key borrada de Keychain."
        } catch {
            providerStatus = "No pude borrar la API key: \(error.localizedDescription)"
        }
    }

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)
                self.micLevel = max(0, min(1, pow(10, Double(db) / 35)))
                self.cursorHUD.update(level: self.micLevel, mode: .recording)
            }
        }
    }

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MT3K Mac Tools/Flow", isDirectory: true)
    }

    private static func openTerminalCommand(_ command: String, title: String) throws {
        let script = """
        #!/bin/zsh
        set -e
        \(command)
        echo
        echo "Listo. Puedes cerrar esta ventana."
        read -k 1 "?Presiona cualquier tecla para cerrar..."
        """
        let safeTitle = title.replacingOccurrences(of: " ", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt3k-\(safeTitle)-\(UUID().uuidString).command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try openInTerminal(scriptPath: url.path)
    }
}

enum FlowPrivacyPane {
    case microphone
    case accessibility
    case inputMonitoring

    var urlString: String {
        switch self {
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
    }
}


private struct FlowTranscriptionResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(_ name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}

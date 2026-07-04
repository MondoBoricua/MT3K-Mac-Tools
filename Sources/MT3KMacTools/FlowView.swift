// MT3K Flow — vista principal y contenido del menu bar.
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import Security
import SwiftUI

struct FlowView: View {
    @EnvironmentObject var flow: FlowState
    @AppStorage("flowProvider") private var provider: FlowProvider = .local
    @AppStorage("flowLanguage") private var language: FlowLanguage = .automatic
    @AppStorage("flowCleanupEnabled") private var cleanupEnabled = true
    @AppStorage("flowMenuBarEnabled") private var flowEnabled = false
    @AppStorage("flowLocalModelID") private var localModelID = "argmaxinc/whisperkit-coreml"
    @AppStorage("flowGroqModel") private var groqModel = "whisper-large-v3"
    @AppStorage("flowOpenAIModel") private var openAIModel = "gpt-4o-transcribe"
    @State private var cloudAPIKey = ""
    @State private var capturingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var selectedHistoryID: String?
    @State private var correctionText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusGrid
                quickStartPanel
                settingsPanel
                providerPanel
                historyPanel
                pipelinePanel
                roadmapPanel
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            flow.refreshPermissions()
            flow.cleanupEnabled = cleanupEnabled
            flow.configureTranscription(provider: provider, model: provider == .groq ? groqModel : openAIModel, language: language)
            flow.applyProvider(provider)
            flow.setFlowActive(flowEnabled)
            flow.loadHistory()
        }
        .onDisappear { stopHotkeyCapture() }
        .onChange(of: cleanupEnabled) { flow.cleanupEnabled = cleanupEnabled }
        .onChange(of: provider) {
            cloudAPIKey = ""
            flow.configureTranscription(provider: provider, model: provider == .groq ? groqModel : openAIModel, language: language)
            flow.applyProvider(provider)
        }
        .onChange(of: language) {
            flow.configureTranscription(provider: provider, model: provider == .groq ? groqModel : openAIModel, language: language)
        }
        .onChange(of: groqModel) {
            flow.configureTranscription(provider: provider, model: provider == .groq ? groqModel : openAIModel, language: language)
        }
        .onChange(of: openAIModel) {
            flow.configureTranscription(provider: provider, model: provider == .groq ? groqModel : openAIModel, language: language)
        }
        .onChange(of: flowEnabled) {
            flow.setFlowActive(flowEnabled)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            FlowIconMark(size: 76)
            VStack(alignment: .leading, spacing: 6) {
                Text("MT3K FLOW")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Text("Dictado nativo para macOS")
                    .font(.title2)
                    .bold()
                Text("Hotkey, captura de audio, transcripción local/cloud, limpieza y pegado cross-app desde la suite.")
                    .foregroundStyle(Theme.textSecondary)
                    .font(.subheadline)
            }
            Spacer()
            Button {
                flowEnabled.toggle()
                flow.setFlowActive(flowEnabled)
            } label: {
                Label(flowEnabled ? "Flow activo" : "Activar Flow", systemImage: flowEnabled ? "mic.fill" : "mic")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(flowEnabled ? Theme.green : Theme.accent)
                    .background((flowEnabled ? Theme.green : Theme.accent).opacity(0.13))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((flowEnabled ? Theme.green : Theme.accent).opacity(0.35)))
            }
            .buttonStyle(.plain)
            .help(flowEnabled ? "Ocultar Flow del menu bar" : "Mostrar Flow en el menu bar para dictar")
            FlowStatusBadge(title: flow.permissionsReady ? "Permisos listos" : "Permisos pendientes",
                            symbol: flow.permissionsReady ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                            color: flow.permissionsReady ? Theme.green : Theme.amber)
        }
        .padding(20)
        .background(Theme.bgCard)
        .overlay(Rectangle().frame(width: 4).foregroundStyle(Theme.accent), alignment: .leading)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var statusGrid: some View {
        Group {
            if flow.permissionsReady {
                FlowPanel(title: "Permisos", symbol: "checkmark.shield.fill") {
                    HStack(spacing: 8) {
                        FlowMiniPermission(title: "Mic", ok: true)
                        FlowMiniPermission(title: "AX", ok: true)
                        FlowMiniPermission(title: "Input", ok: true)
                        Spacer()
                        Button("Revisar permisos") {
                            flow.refreshPermissions()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    FlowPermissionCard(
                        title: "Micrófono",
                        detail: flow.micPermission.rawValue,
                        symbol: "mic.fill",
                        state: flow.micPermission,
                        request: { Task { await flow.requestMicrophone() } },
                        openSettings: { flow.openPrivacyPane(.microphone) }
                    )
                    FlowPermissionCard(
                        title: "Accessibility",
                        detail: flow.accessibilityPermission.rawValue,
                        symbol: "cursorarrow.motionlines",
                        state: flow.accessibilityPermission,
                        request: { flow.requestAccessibility() },
                        openSettings: { flow.openPrivacyPane(.accessibility) }
                    )
                    FlowPermissionCard(
                        title: "Input Monitoring",
                        detail: flow.inputMonitoringPermission.rawValue,
                        symbol: "keyboard.fill",
                        state: flow.inputMonitoringPermission,
                        request: { flow.requestInputMonitoring() },
                        openSettings: { flow.openPrivacyPane(.inputMonitoring) }
                    )
                }
            }
        }
    }

    private var quickStartPanel: some View {
        FlowPanel(title: "Prueba de captura", symbol: "waveform") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.accent)
                            .frame(width: max(8, 240 * flow.micLevel))
                    }
                    .frame(width: 240, height: 14)

                    Text(flow.isRecording ? "Grabando..." : flow.lastClipDuration)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(flow.isRecording ? Theme.accent : Theme.textSecondary)

                    Spacer()
                }

                Text(flow.status)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    FlowActionButton(
                        title: flow.isRecording ? "Detener prueba" : "Probar micrófono",
                        symbol: flow.isRecording ? "stop.fill" : "record.circle",
                        color: flow.isRecording ? .red : Theme.accent,
                        action: { flow.toggleMicTest() }
                    )

                    FlowActionButton(
                        title: "Mostrar archivo",
                        symbol: "folder.fill",
                        color: Theme.blue,
                        action: { flow.revealLastClip() }
                    )
                    .disabled(flow.lastClipPath.isEmpty)
                }
            }
        }
    }

    private var settingsPanel: some View {
        FlowPanel(title: "Configuración", symbol: "slider.horizontal.3") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Provider").foregroundStyle(Theme.textSecondary)
                    Picker("Provider", selection: $provider) {
                        ForEach(FlowProvider.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                GridRow {
                    Text("Idioma").foregroundStyle(Theme.textSecondary)
                    Picker("Idioma", selection: $language) {
                        ForEach(FlowLanguage.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                GridRow {
                    Text("Hotkey").foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        Text(capturingHotkey ? "Presiona una combinación..." : flow.currentHotkey.display)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospaced()
                            .frame(minWidth: 180, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.06))
                            .clipShape(.rect(cornerRadius: 8))
                        Button(capturingHotkey ? "Cancel" : "Cambiar") {
                            capturingHotkey ? stopHotkeyCapture() : startHotkeyCapture()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                GridRow {
                    Text("Opciones").foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 14) {
                        Toggle("Limpieza con gemma3:1b (Ollama)", isOn: $cleanupEnabled)
                        Toggle("Activar Flow en menu bar", isOn: $flowEnabled)
                    }
                }
            }
            .font(.system(size: 13, weight: .medium))

            Text(flow.hotkeyStatus)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func startHotkeyCapture() {
        stopHotkeyCapture()
        capturingHotkey = true
        flow.hotkeyStatus = "Presiona la nueva combinación de teclas."
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard let hotkey = FlowHotkey.from(event: event) else { return nil }
            flow.updateHotkey(hotkey, flowActive: flowEnabled)
            stopHotkeyCapture()
            return nil
        }
    }

    private func stopHotkeyCapture() {
        capturingHotkey = false
        if let hotkeyMonitor {
            NSEvent.removeMonitor(hotkeyMonitor)
            self.hotkeyMonitor = nil
        }
    }

    @ViewBuilder
    private var providerPanel: some View {
        if provider == .local {
            localKitPanel
        } else {
            cloudProviderPanel
        }
    }

    private var localKitPanel: some View {
        FlowPanel(title: "Provider local", symbol: "externaldrive.badge.person.crop") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Flow transcribe local con WhisperKit (\(flow.localModelVariant)) y limpia con gemma3:1b. 100% offline. Se activa al elegir el provider Local.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Hugging Face").foregroundStyle(Theme.textSecondary)
                        TextField("argmaxinc/whisperkit-coreml", text: $localModelID)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 360)
                    }
                }
                .font(.system(size: 13, weight: .medium))

                Text(flow.localModelStatus)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    FlowActionButton(title: "Abrir modelo", symbol: "arrow.up.right.square.fill", color: Theme.blue) {
                        flow.openHuggingFaceModel(localModelID)
                    }
                    FlowActionButton(
                        title: flow.localModelLoading ? "Descargando…" : "Descargar modelo",
                        symbol: flow.localModelLoading ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill",
                        color: Theme.green
                    ) {
                        Task { await flow.preloadLocalModel() }
                    }
                    .disabled(flow.localModelLoading)
                }
            }
        }
    }

    private var cloudProviderPanel: some View {
        FlowPanel(title: "Provider cloud", symbol: "cloud.fill") {
            VStack(alignment: .leading, spacing: 12) {
                FlowStatusBadge(
                    title: provider.rawValue,
                    symbol: provider == .groq ? "bolt.fill" : "sparkles",
                    color: provider == .groq ? Theme.amber : Theme.blue
                )

                Text(flow.providerStatus)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Modelo").foregroundStyle(Theme.textSecondary)
                        TextField(provider == .groq ? "whisper-large-v3" : "gpt-4o-transcribe", text: cloudModelBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                    }
                    GridRow {
                        Text("API key").foregroundStyle(Theme.textSecondary)
                        VStack(alignment: .leading, spacing: 6) {
                            SecureField(apiKeyPlaceholder, text: $cloudAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 360)
                            Text(apiKeyStatus)
                                .font(.caption)
                                .foregroundStyle(apiKeySaved ? Theme.green : Theme.textSecondary)
                        }
                    }
                }
                .font(.system(size: 13, weight: .medium))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    FlowActionButton(title: "Guardar API key", symbol: "lock.fill", color: Theme.green) {
                        flow.saveAPIKey(cloudAPIKey, for: provider)
                        cloudAPIKey = ""
                    }
                    FlowActionButton(title: "Abrir API keys", symbol: "key.fill", color: Theme.blue) {
                        flow.openProviderConsole(provider)
                    }
                    FlowActionButton(title: "Borrar API key", symbol: "trash.fill", color: .red) {
                        flow.deleteAPIKey(for: provider)
                    }
                    .disabled(!apiKeySaved)
                    FlowActionButton(title: "Usar local", symbol: "externaldrive.fill", color: Theme.green) {
                        provider = .local
                    }
                }
            }
        }
    }

    private var cloudModelBinding: Binding<String> {
        Binding(
            get: { provider == .groq ? groqModel : openAIModel },
            set: { value in
                if provider == .groq {
                    groqModel = value
                } else {
                    openAIModel = value
                }
            }
        )
    }

    private var apiKeySaved: Bool {
        provider == .groq ? flow.groqKeySaved : flow.openAIKeySaved
    }

    private var apiKeyStatus: String {
        if apiKeySaved {
            return "\(provider.rawValue) API key guardada en Keychain."
        }
        return "Pega aquí la API key de \(provider.rawValue). No se muestra ni se guarda en texto plano."
    }

    private var apiKeyPlaceholder: String {
        provider == .groq ? "gsk_..." : "sk-..."
    }

    private var pipelinePanel: some View {
        FlowPanel(title: "Pipeline", symbol: "point.3.connected.trianglepath.dotted") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                FlowStepCard(title: "Hotkey", detail: "Carbon toggle listo para conectar", symbol: "keyboard", ready: false)
                FlowStepCard(title: "Audio", detail: "Mic test y metering activo", symbol: "waveform", ready: true)
                FlowStepCard(title: "Transcripción", detail: "WhisperKit local · Groq · OpenAI", symbol: "text.bubble", ready: true)
                FlowStepCard(title: "Cleanup", detail: "Reglas + Ollama opcional", symbol: "wand.and.stars", ready: false)
                FlowStepCard(title: "Paste", detail: "AX + Cmd-V con detección terminal", symbol: "doc.on.clipboard", ready: false)
                FlowStepCard(title: "HUD", detail: "Pastilla flotante con waveform", symbol: "rectangle.inset.filled", ready: false)
            }
        }
    }

    private var historyPanel: some View {
        FlowPanel(title: "History y aprendizaje", symbol: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Corrige el texto final cuando Flow se equivoque. La corrección se guarda en history y aprende pares para reemplazos futuros.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                Text(flow.historyStatus)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                if flow.history.isEmpty {
                    ContentUnavailableView("Sin dictados todavía", systemImage: "text.bubble", description: Text("Cuando Flow transcriba, las entradas aparecerán aquí para corregir palabras. Las pruebas de micrófono también dejan una entrada temporal."))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(flow.history.prefix(8)) { entry in
                            FlowHistoryRow(
                                entry: entry,
                                isSelected: selectedHistoryID == entry.id,
                                correctionText: selectedHistoryID == entry.id ? $correctionText : .constant(entry.cleaned),
                                select: {
                                    selectedHistoryID = entry.id
                                    correctionText = entry.cleaned
                                },
                                save: {
                                    flow.updateHistoryCorrection(entry, cleaned: correctionText)
                                },
                                delete: {
                                    flow.deleteHistoryEntry(entry)
                                    if selectedHistoryID == entry.id {
                                        selectedHistoryID = nil
                                        correctionText = ""
                                    }
                                }
                            )
                        }
                    }
                }

                if !flow.learnedReplacements.isEmpty {
                    Divider()
                    Text("Aprendido")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                    FlowTagCloud(items: flow.learnedReplacements.suffix(10).map { "\($0.from) → \($0.to)" })
                }
            }
        }
    }

    private var roadmapPanel: some View {
        FlowPanel(title: "Siguiente implementación", symbol: "list.bullet.rectangle.fill") {
            VStack(alignment: .leading, spacing: 8) {
                FlowRoadmapRow(text: "AudioCapture 16 kHz mono Float32 + DSP puro testeable.", done: false)
                FlowRoadmapRow(text: "Paster con AX insert y fallback único Cmd-V para terminales.", done: false)
                FlowRoadmapRow(text: "CloudTranscriber compatible Groq/OpenAI con API keys en Keychain.", done: false)
                FlowRoadmapRow(text: "WhisperKit local + limpieza gemma3:1b (transcripción 100% offline).", done: true)
                FlowRoadmapRow(text: "HUD NSPanel multi-monitor siguiendo el cursor.", done: false)
            }
        }
    }
}

struct FlowMenuBarContent: View {
    @EnvironmentObject var flow: FlowState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("flowMenuBarEnabled") private var flowEnabled = false
    @AppStorage("flowProvider") private var provider: FlowProvider = .local
    @AppStorage("flowLanguage") private var language: FlowLanguage = .automatic
    @AppStorage("flowGroqModel") private var groqModel = "whisper-large-v3"
    @AppStorage("flowOpenAIModel") private var openAIModel = "gpt-4o-transcribe"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FlowIconMark(size: 24)
                Text("MT3K Flow")
                    .font(.headline)
                Spacer()
            }

            Text(flow.status)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                FlowMiniPermission(title: "Mic", ok: flow.micPermission.ok)
                FlowMiniPermission(title: "AX", ok: flow.accessibilityPermission.ok)
                FlowMiniPermission(title: "Keys", ok: flow.inputMonitoringPermission.ok)
            }

            Divider()

            Picker("Modo", selection: $language) {
                ForEach(FlowLanguage.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .onChange(of: language) {
                configureFlowLanguage()
            }

            Button {
                flow.toggleMicTest()
            } label: {
                Label(flow.isRecording ? "Detener prueba" : "Probar micrófono",
                      systemImage: flow.isRecording ? "stop.fill" : "record.circle")
            }

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Abrir Flow", systemImage: "macwindow")
            }

            Button {
                flowEnabled = false
                flow.setFlowActive(false)
            } label: {
                Label("Desactivar Flow", systemImage: "xmark.circle")
            }
        }
        .padding(12)
        .frame(width: 290)
        .task {
            configureFlowLanguage()
        }
    }

    private func configureFlowLanguage() {
        flow.configureTranscription(
            provider: provider,
            model: provider == .groq ? groqModel : openAIModel,
            language: language
        )
    }
}

struct FlowMenuBarLabel: View {
    let isRecording: Bool
    let permissionsReady: Bool

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(iconColor)
        .frame(width: 22, height: 20)
        .contentShape(Rectangle())
        .fixedSize()
    }

    private var symbolName: String {
        isRecording ? "waveform.circle.fill" : "waveform"
    }

    private var iconColor: Color {
        if isRecording { return .red }
        if !permissionsReady { return Theme.amber }
        return .white.opacity(0.94)
    }
}


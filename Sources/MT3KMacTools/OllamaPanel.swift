import Foundation
import SwiftUI
import AppKit

// MARK: - Models

struct OllamaModel: Identifiable, Hashable {
    let name: String              // ej. "gemma4:9b"
    let size: String              // ej. "5.4 GB"
    let modified: String          // ej. "3 días"
    let isCloud: Bool             // tag termina en :cloud (Ollama 0.24+)
    var id: String { name }
}

private struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
        let size: Int64?
        let modified_at: String?
    }
    let models: [Model]
}

struct OllamaSuggestion: Identifiable, Hashable {
    let id: String                // tag = name
    let label: String
    let category: String
    let summary: String
    var pullArg: String { id }
}

enum OllamaCatalog {
    // Actualizado mayo 2026 — verificado contra ollama.com/library.
    // Llama 4, Gemma 4, Qwen 3.6, Kimi K2.6, GLM-5.1, Phi 4 son los actuales.
    static let popular: [OllamaSuggestion] = [
        // General — top tier
        .init(id: "llama4:scout", label: "Llama 4 Scout", category: "General",
              summary: "Meta · top open-source 2026, balanced quality. Requiere ~25 GB."),
        .init(id: "gemma4:9b", label: "Gemma 4 9B", category: "General",
              summary: "Google · tool calling + visión nativa, ~6 GB. (Abril 2026)"),
        .init(id: "gemma4:27b", label: "Gemma 4 27B", category: "General",
              summary: "Google · top quality, multimodal. ~18 GB."),
        .init(id: "qwen3.6:8b", label: "Qwen 3.6 8B", category: "General",
              summary: "Alibaba · sucesor estable de qwen3.5, multilingüe."),
        .init(id: "llama3.3:70b", label: "Llama 3.3 70B", category: "General",
              summary: "Meta · sigue siendo sólido para rigs con >40 GB."),
        .init(id: "llama3.2:3b", label: "Llama 3.2 3B", category: "General",
              summary: "Liviano (2 GB) para chat rápido y RAG."),
        .init(id: "phi4:14b", label: "Phi-4 14B", category: "General",
              summary: "Microsoft · razonamiento bien equilibrado, ~9 GB."),
        .init(id: "mistral-small:24b", label: "Mistral Small 24B", category: "General",
              summary: "Mistral · denso y rápido, top para inference local."),

        // Coding — los duros de 2026
        .init(id: "qwen3.6:27b", label: "Qwen 3.6 27B", category: "Coding",
              summary: "★ 77.2% SWE-bench. Top dense coder open-source. ~22 GB VRAM."),
        .init(id: "kimi-k2.6", label: "Kimi K2.6", category: "Coding",
              summary: "Moonshot · frontier MoE, 87/100 real-world coding score."),
        .init(id: "glm-5.1", label: "GLM-5.1", category: "Coding",
              summary: "Zhipu · agentic engineering, SOTA en SWE-Bench Pro."),
        .init(id: "qwen2.5-coder:7b", label: "Qwen 2.5 Coder 7B", category: "Coding",
              summary: "Budget option, ~4 GB. Sigue siendo bueno."),
        .init(id: "qwen2.5-coder:14b", label: "Qwen 2.5 Coder 14B", category: "Coding",
              summary: "Mejor calidad de código mid-tier. ~9 GB."),

        // Reasoning
        .init(id: "deepseek-r1:14b", label: "DeepSeek R1 14B", category: "Reasoning",
              summary: "DeepSeek · chain-of-thought. ~9 GB."),
        .init(id: "deepseek-r1:32b", label: "DeepSeek R1 32B", category: "Reasoning",
              summary: "Mejor razonamiento, ~22 GB."),

        // Embeddings (sin cambios — siguen siendo los stock)
        .init(id: "nomic-embed-text", label: "Nomic Embed", category: "Embeddings",
              summary: "Para embeddings de texto (RAG)."),
        .init(id: "mxbai-embed-large", label: "MxBai Embed Large", category: "Embeddings",
              summary: "Embeddings premium para búsqueda semántica."),

        // Visión / multimodal — Gemma 4 ya tiene visión, otros opciones:
        .init(id: "llava:13b", label: "LLaVA 13B", category: "Visión",
              summary: "Multimodal clásico, acepta imágenes."),
        .init(id: "moondream:1.8b", label: "Moondream 1.8B", category: "Visión",
              summary: "Visión liviana, ~1.7 GB."),

        // Uncensored / abliterated — útil para Red Team / Security Lab cuando los
        // safety filters bloquean discusión legítima de CVEs, payloads, malware.
        // Curado para Macs (8-32 GB RAM). Verificado contra ollama.com mayo 2026.
        .init(id: "joe-speedboat/Gemma-4-Uncensored-HauhauCS-Aggressive:e4b",
              label: "Gemma 4 Uncensored Aggressive (HauhauCS)",
              category: "Uncensored",
              summary: "★ 6.3 GB · 128K context · visión. Refusal removed, agresivo. Excelente para Macs medianos. (uploader: joe-speedboat)"),
        .init(id: "fredrezones55/Qwen3.6-27B-Uncensored-HauhauCS-Balanced:IQ4_XS",
              label: "Qwen 3.6 27B Uncensored Balanced (HauhauCS)",
              category: "Uncensored",
              summary: "★ 16 GB · 256K context · visión. Refusal removed pero razona antes con disclaimer breve. Ideal para Macs 32+ GB."),
        .init(id: "VladimirGav/Gemma4-26B-16GB-VRAM-Uncensored",
              label: "Gemma 4 26B Uncensored (16GB VRAM)",
              category: "Uncensored",
              summary: "Tunado para Mac Studio/MBP con 16 GB. Versión cuantizada de Gemma 4 sin guardrails."),
        .init(id: "VladimirGav/Qwen3.6-27B-16GB-VRAM-Uncensored",
              label: "Qwen 3.6 27B Uncensored (16GB VRAM)",
              category: "Uncensored",
              summary: "Qwen 3.6 27B cuantizado para Macs 16 GB unified memory."),
        .init(id: "Agen/gemma-4-26B-A4B-it-uncensored-heretic",
              label: "Gemma 4 26B Heretic Uncensored",
              category: "Uncensored",
              summary: "Variante abliterated (refusal weights removed quirúrgicamente), no fine-tuned."),
        .init(id: "dolphin3:8b",
              label: "Dolphin 3 8B",
              category: "Uncensored",
              summary: "Eric Hartford · serie clásica, dataset sin reinforcement de refusal. Function calling. ~4.7 GB."),
        .init(id: "joe-speedboat/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive",
              label: "Qwen 3.6 35B A3B Uncensored Aggressive",
              category: "Uncensored",
              summary: "MoE 35B (3B activos). Aggressive variant. Para Macs con 32+ GB."),
        .init(id: "dolphin-mixtral:8x7b",
              label: "Dolphin Mixtral 8x7B",
              category: "Uncensored",
              summary: "MoE clásico Mixtral con dataset Dolphin. ~26 GB. Para Macs con buen RAM."),
    ]

    static var categories: [String] {
        var seen: Set<String> = []
        return popular.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}

// MARK: - State

@MainActor
final class OllamaState: ObservableObject {
    @Published var installed: Bool = false
    @Published var version: String = ""
    @Published var serverRunning: Bool = false
    @Published var models: [OllamaModel] = []
    @Published var runningModels: [String] = []
    @Published var busy: Bool = false
    @Published var busyPullingID: String?
    @Published var busyDeletingID: String?

    private weak var log: LogStore?

    func configure(log: LogStore) { self.log = log }

    func bootstrap() async {
        await refresh()
    }

    func refresh() async {
        let installedCheck = (try? await runShell(executable: "/bin/zsh", args: ["-lc", "command -v ollama >/dev/null 2>&1 && echo yes || echo no"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "no"
        installed = installedCheck == "yes"

        if installed {
            version = (try? await runShell(executable: "/bin/zsh", args: ["-lc", "ollama --version 2>&1 | head -1"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Use the JSON API — más robusto que parsear `ollama list`.
            // GET http://localhost:11434/api/tags → { "models": [...] }
            let (fetched, alive) = await fetchTagsFromAPI()
            serverRunning = alive
            models = fetched

            if serverRunning {
                let psOutput = (try? await runShell(executable: "/bin/zsh", args: ["-lc", "ollama ps 2>&1"])) ?? ""
                runningModels = parseRunning(psOutput)
            } else {
                runningModels = []
            }
        } else {
            version = ""
            serverRunning = false
            models = []
            runningModels = []
        }
    }

    /// Fetch installed models via Ollama's HTTP API. Returns (models, serverAlive).
    private func fetchTagsFromAPI() async -> ([OllamaModel], Bool) {
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            return ([], false)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return ([], false)
            }
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let models = decoded.models.map { raw in
                let cloud = Self.isCloudModel(raw.name)
                return OllamaModel(
                    name: raw.name,
                    size: cloud ? "Ollama Cloud" : formatBytes(raw.size ?? 0),
                    modified: relativeDate(raw.modified_at),
                    isCloud: cloud
                )
            }.sorted { $0.name < $1.name }
            return (models, true)
        } catch {
            return ([], false)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func relativeDate(_ iso: String?) -> String {
        guard let iso, let date = Self.iso8601.date(from: iso) ?? Self.iso8601Fallback.date(from: iso) else {
            return "—"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Detecta modelos hosted en Ollama Cloud. Soporta ambos formatos:
    /// - Tag literal `:cloud` (ej. `glm-4.7:cloud`, `qwen3-coder-next:cloud`)
    /// - Tag con tamaño + `-cloud` (ej. `gemma4:31b-cloud`, `gpt-oss:120b-cloud`)
    nonisolated static func isCloudModel(_ name: String) -> Bool {
        guard let colon = name.lastIndex(of: ":") else { return false }
        let tag = name[name.index(after: colon)...]
        return tag == "cloud" || tag.hasSuffix("-cloud")
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseRunning(_ raw: String) -> [String] {
        raw.split(whereSeparator: \.isNewline)
            .dropFirst()                                        // header
            .compactMap { $0.split(separator: " ").first.map(String.init) }
            .filter { !$0.isEmpty && $0.lowercased() != "name" }
    }

    // MARK: - Actions

    func installOllama() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        log?.append("Instalando ollama vía brew...", level: .info)
        do {
            _ = try await runShell(executable: "/bin/zsh", args: ["-lc", "brew install ollama"])
            log?.append("ollama instalado.", level: .success)
        } catch {
            log?.append("brew install ollama falló: \(error.localizedDescription)", level: .error)
        }
        await refresh()
    }

    func startServer() {
        // Daemonize via brew services so it persiste reboot.
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        if ! command -v ollama >/dev/null 2>&1; then
            echo "✗ ollama no instalado."
            read -k 1 "?Presiona cualquier tecla..."
            exit 1
        fi
        echo "→ Iniciando ollama serve (brew services)..."
        brew services start ollama
        sleep 1
        echo ""
        echo "Status:"
        brew services info ollama
        read -k 1 "?Presiona cualquier tecla para cerrar..."
        """
        openCommandScript(script, title: "ollama-start")
        log?.append("Iniciando ollama serve en Terminal...", level: .info)
    }

    func stopServer() {
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        echo "→ Parando ollama serve..."
        brew services stop ollama
        sleep 1
        brew services info ollama
        read -k 1 "?Presiona cualquier tecla para cerrar..."
        """
        openCommandScript(script, title: "ollama-stop")
    }

    func pull(_ tag: String) async {
        guard !busy, busyPullingID == nil else { return }
        busyPullingID = tag
        defer { busyPullingID = nil }
        log?.append("Pulling \(tag)...", level: .info)
        // Pull en Terminal porque puede tardar varios GB y la TUI muestra progreso bonito.
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        echo "→ ollama pull \(tag)"
        ollama pull \(tag)
        STATUS=$?
        echo ""
        if [ $STATUS -eq 0 ]; then echo "✓ \(tag) listo."; else echo "✗ Falló pull (\\$STATUS)."; fi
        read -k 1 "?Presiona cualquier tecla para cerrar..."
        """
        openCommandScript(script, title: "ollama-pull-\(tag.replacingOccurrences(of: ":", with: "-"))")
        log?.append("Pull lanzado en Terminal.", level: .info)
    }

    func delete(_ name: String) async {
        guard !busy, busyDeletingID == nil else { return }
        busyDeletingID = name
        defer { busyDeletingID = nil }
        do {
            _ = try await runShell(executable: "/bin/zsh", args: ["-lc", "ollama rm \(name.shellQuoted)"])
            log?.append("Modelo \(name) eliminado.", level: .success)
        } catch {
            log?.append("Error eliminando \(name): \(error.localizedDescription)", level: .error)
        }
        await refresh()
    }

    func chat(_ name: String) {
        let script = """
        #!/bin/zsh
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        clear
        echo "═══════════════════════════════════════════════════"
        echo " Chat con \(name)"
        echo " (escribe /bye para salir, /clear para limpiar)"
        echo "═══════════════════════════════════════════════════"
        ollama run \(name)
        """
        openCommandScript(script, title: "ollama-chat-\(name.replacingOccurrences(of: ":", with: "-"))")
        log?.append("Chat con \(name) abierto en Terminal.", level: .info)
    }

    private func openCommandScript(_ content: String, title: String) {
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt3k-\(title)-\(UUID().uuidString).command")
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try openInTerminal(scriptPath: url.path)
        } catch {
            log?.append("Error abriendo Terminal: \(error.localizedDescription)", level: .error)
        }
    }
}

// MARK: - View

struct OllamaPanel: View {
    @EnvironmentObject var log: LogStore
    @StateObject private var state = OllamaState()
    @State private var customPullTag: String = ""
    @State private var categoryFilter: String = ""

    var body: some View {
        SystemPanel(title: "Ollama — modelos locales", symbol: "brain.head.profile") {
            statusRow

            if state.installed {
                serverControls
                Divider()
                installedModelsSection
                Divider()
                suggestionsSection
                Divider()
                customPullSection
            } else {
                installCTA
            }
        }
        .task {
            state.configure(log: log)
            await state.bootstrap()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText).font(.system(size: 13, weight: .semibold))
                Text(statusDetail).font(.caption).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").padding(4)
            }
            .buttonStyle(.borderless)
            .help("Re-verificar estado")
        }
    }

    private var statusColor: Color {
        if !state.installed { return Theme.textSecondary }
        return state.serverRunning ? Theme.green : Theme.amber
    }

    private var statusText: String {
        if !state.installed { return "Ollama no instalado" }
        return state.serverRunning ? "Ollama corriendo" : "Ollama instalado · servidor parado"
    }

    private var statusDetail: String {
        if !state.installed { return "Instálalo con `brew install ollama`" }
        let v = state.version.isEmpty ? "" : "\(state.version) · "
        let modelCount = state.models.count
        let running = state.runningModels.isEmpty ? "ninguno corriendo" : "corriendo: \(state.runningModels.joined(separator: ", "))"
        return "\(v)\(modelCount) modelo(s) descargado(s) · \(running)"
    }

    private var installCTA: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").foregroundColor(Theme.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Instalar Ollama").bold()
                Text("Necesario para correr LLMs locales (Llama 3, Qwen, DeepSeek R1, etc.) sin enviar nada a la nube.")
                    .font(.caption).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            SystemActionButton(title: state.busy ? "Instalando..." : "brew install ollama", symbol: "arrow.down.circle.fill", color: Theme.accent) {
                Task { await state.installOllama() }
            }
            .disabled(state.busy)
        }
    }

    private var serverControls: some View {
        HStack(spacing: 8) {
            if state.serverRunning {
                SystemActionButton(title: "Parar servidor", symbol: "stop.circle.fill", color: Theme.orange) {
                    state.stopServer()
                }
            } else {
                SystemActionButton(title: "Iniciar servidor", symbol: "play.circle.fill", color: Theme.green) {
                    state.startServer()
                }
            }
            SystemActionButton(title: "Refrescar", symbol: "arrow.clockwise", color: Theme.blue) {
                Task { await state.refresh() }
            }
        }
    }

    private var installedModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill").foregroundColor(Theme.accent)
                Text("Modelos descargados (\(state.models.count))").font(.system(size: 12, weight: .semibold))
            }
            if state.models.isEmpty {
                Text(state.serverRunning ? "Aún no descargas ningún modelo. Usa la lista de sugerencias o el pull custom abajo." : "Inicia el servidor para ver modelos.")
                    .font(.caption).foregroundColor(Theme.textSecondary)
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(state.models) { model in
                        installedModelRow(model)
                    }
                }
            }
        }
    }

    private func installedModelRow(_ model: OllamaModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: model.isCloud ? "cloud.fill" : "cube.fill")
                .foregroundColor(model.isCloud ? Theme.amber : Theme.blue)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.name).font(.system(size: 13, weight: .semibold))
                    if model.isCloud {
                        Text("cloud")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.amber.opacity(0.18))
                            .foregroundColor(Theme.amber)
                            .clipShape(Capsule())
                    }
                }
                Text("\(model.size) · \(model.modified)")
                    .font(.caption2).foregroundColor(Theme.textSecondary)
            }
            Spacer()
            Button("Chat") { state.chat(model.name) }
                .buttonStyle(.bordered).controlSize(.small)
            Button {
                Task { await state.delete(model.name) }
            } label: {
                Image(systemName: "trash").foregroundColor(Theme.sevCritical)
            }
            .buttonStyle(.borderless)
            .disabled(state.busyDeletingID == model.name)
            .help("Eliminar este modelo")
        }
        .padding(8)
        .background(Theme.bgDark)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundColor(Theme.amber)
                Text("Sugeridos").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("Categoría", selection: $categoryFilter) {
                    Text("Todas").tag("")
                    ForEach(OllamaCatalog.categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 160)
            }

            if categoryFilter == "Uncensored" {
                uncensoredNotice
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 8)], spacing: 8) {
                ForEach(filteredSuggestions) { sug in
                    suggestionCard(sug)
                }
            }
        }
    }

    private var uncensoredNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(Theme.sevCritical)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("Modelos sin guardrails").font(.caption.bold())
                Text("Útiles para análisis legítimo de CVEs/payloads/malware donde modelos alineados rehusan responder. Verifica las recomendaciones antes de ejecutarlas — no validan dañinidad, solo cumplen. Uso bajo tu responsabilidad.")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Theme.sevCritical.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.sevCritical.opacity(0.30)))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var filteredSuggestions: [OllamaSuggestion] {
        let installedNames = Set(state.models.map { $0.name })
        return OllamaCatalog.popular
            .filter { categoryFilter.isEmpty || $0.category == categoryFilter }
            .filter { !installedNames.contains($0.id) }
    }

    private func suggestionCard(_ sug: OllamaSuggestion) -> some View {
        let isPulling = state.busyPullingID == sug.id
        let isUncensored = sug.category == "Uncensored"
        let chipColor = isUncensored ? Theme.sevCritical : Theme.accent
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(sug.label).font(.system(size: 13, weight: .semibold))
                    Text(sug.category).font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(chipColor.opacity(0.18))
                        .foregroundColor(chipColor)
                        .clipShape(Capsule())
                }
                Text(sug.summary).font(.caption).foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(isPulling ? "..." : "Pull") {
                Task { await state.pull(sug.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!state.serverRunning || isPulling)
        }
        .padding(10)
        .background(Theme.bgDark)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isUncensored ? Theme.sevCritical.opacity(0.35) : Theme.border)
        )
        .clipShape(.rect(cornerRadius: 8))
    }

    private var customPullSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc.fill").foregroundColor(Theme.blue)
                Text("Pull custom").font(.system(size: 12, weight: .semibold))
            }
            HStack(spacing: 8) {
                TextField("ej. llama3.2:latest, mistral-nemo, codestral", text: $customPullTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Button("Pull") {
                    let tag = customPullTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !tag.isEmpty else { return }
                    Task { await state.pull(tag) }
                    customPullTag = ""
                }
                .buttonStyle(.bordered)
                .disabled(!state.serverRunning)
            }
            Text("Catálogo completo: https://ollama.com/library").font(.caption2).foregroundColor(Theme.textSecondary)
        }
    }
}

import SwiftUI

struct BrowsersView: View {
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var auth: AdminAuth
    @EnvironmentObject var brew: BrewState

    @State private var braveOutput: String = ""
    @State private var braveStatus: OutputStatus = .none
    @State private var braveBusy: String? = nil
    @State private var confirmAction: ConfirmAction? = nil
    @State private var sourceText: String? = nil
    @State private var sourceTitle: String = ""

    struct ConfirmAction: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let runner: () -> Void
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroHeader
                braveCard
                browserInstallSection
                LogView()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .alert(
            confirmAction?.title ?? "",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            presenting: confirmAction
        ) { item in
            Button("Continuar", role: .destructive) { item.runner() }
            Button("Cancelar", role: .cancel) {}
        } message: { item in
            Text(item.message)
        }
        .sheet(isPresented: Binding(
            get: { sourceText != nil },
            set: { if !$0 { sourceText = nil } }
        )) {
            sourceSheet
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BROWSERS").font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Theme.accent)
            Text("Endurece y limpia features de navegadores").font(.title2).bold()
            Text("Cambios vía Managed Preferences (políticas a nivel sistema). Reversibles en cualquier momento.")
                .foregroundColor(Theme.textSecondary)
                .font(.subheadline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(Rectangle().frame(width: 4).foregroundColor(Theme.accent), alignment: .leading)
        .cornerRadius(12)
    }

    private var braveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 36))
                    .foregroundColor(Theme.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Brave Debloat").font(.title3).bold()
                    Text("Deshabilita Rewards, Wallet, VPN, AI Chat, News, Talk, Playlist, Speedreader, Wayback Machine, P3A, Stats Ping y Web Discovery.")
                        .foregroundColor(Theme.textSecondary)
                        .font(.subheadline)
                }
            }

            HStack(spacing: 8) {
                BadgePill(text: "Requiere admin", color: Theme.amber)
                BadgePill(text: "macOS", color: Theme.blue)
                if auth.hasSession {
                    BadgePill(text: "Sesión admin activa", color: Theme.green)
                }
                Spacer()
                Button("Ver debloat") { showSource(named: "brave_debloat.sh") }
                    .buttonStyle(.link)
                Button("Ver restore") { showSource(named: "brave_restore.sh") }
                    .buttonStyle(.link)
            }

            if braveStatus != .none {
                OutputBox(text: braveOutput, status: braveStatus)
            }

            HStack(spacing: 12) {
                ActionButton(title: "Ejecutar Debloat", systemImage: "play.fill", color: Theme.accent,
                             busy: braveBusy == "debloat",
                             disabled: braveBusy != nil) {
                    confirmAction = .init(
                        title: "Ejecutar Brave Debloat",
                        message: "Va a crear/sobrescribir /Library/Managed Preferences/com.brave.Browser.plist con políticas restrictivas. macOS pedirá tu contraseña de administrador."
                    ) {
                        Task { await runDebloat() }
                    }
                }

                ActionButton(title: "Verificar políticas", systemImage: "checkmark.shield", color: Theme.blue,
                             busy: braveBusy == "verify",
                             disabled: braveBusy != nil) {
                    Task { await verify() }
                }

                ActionButton(title: "Restaurar", systemImage: "arrow.uturn.backward", color: .clear, outline: true,
                             busy: braveBusy == "restore",
                             disabled: braveBusy != nil) {
                    confirmAction = .init(
                        title: "Restaurar Brave",
                        message: "Va a eliminar /Library/Managed Preferences/com.brave.Browser.plist. Brave volverá al comportamiento por defecto. macOS pedirá contraseña."
                    ) {
                        Task { await restore() }
                    }
                }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var browserInstallSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Instalar navegadores").font(.headline)
                Spacer()
                if !brew.brewInstalled {
                    BadgePill(text: "Homebrew requerido", color: Theme.amber)
                }
            }
            ForEach(Catalog.items(in: .browsers)) { item in
                InstallRow(
                    item: item,
                    isSelected: false,
                    selectionEnabled: false,
                    onSelectionChange: { _ in }
                )
                if item.id != Catalog.items(in: .browsers).last?.id {
                    Divider().background(Theme.border)
                }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    // MARK: actions

    @MainActor
    private func runDebloat() async {
        braveBusy = "debloat"
        defer { braveBusy = nil }
        log.append("Ejecutando Brave Debloat...", level: .info)
        braveStatus = .info
        braveOutput = "Solicitando permisos de administrador..."
        do {
            try auth.acquire(prompt: "MT3K Brave Debloat")
            let url = try resolveScript("brave_debloat.sh")
            let output = try await auth.runPrivileged(scriptPath: url.path)
            braveOutput = output.isEmpty ? "Listo." : output
            braveStatus = .success
            log.append("Políticas de Brave instaladas.", level: .success)
        } catch {
            braveOutput = error.localizedDescription
            braveStatus = .error
            log.append("Error: \(error.localizedDescription)", level: .error)
        }
    }

    @MainActor
    private func restore() async {
        braveBusy = "restore"
        defer { braveBusy = nil }
        log.append("Restaurando Brave...", level: .info)
        braveStatus = .info
        braveOutput = "Solicitando permisos..."
        do {
            try auth.acquire(prompt: "MT3K Restaurar Brave")
            let url = try resolveScript("brave_restore.sh")
            let output = try await auth.runPrivileged(scriptPath: url.path)
            braveOutput = output.isEmpty ? "Listo." : output
            braveStatus = .success
            log.append("Brave restaurado.", level: .success)
        } catch {
            braveOutput = error.localizedDescription
            braveStatus = .error
            log.append("Error: \(error.localizedDescription)", level: .error)
        }
    }

    @MainActor
    private func verify() async {
        braveBusy = "verify"
        defer { braveBusy = nil }
        log.append("Verificando políticas...", level: .info)
        let path = "/Library/Managed Preferences/com.brave.Browser.plist"
        guard FileManager.default.fileExists(atPath: path) else {
            braveOutput = "No se encontró \(path).\nEjecuta Brave Debloat primero."
            braveStatus = .error
            log.append("Políticas no instaladas.", level: .warn)
            return
        }
        do {
            let output = try await runShell(executable: "/usr/bin/plutil", args: ["-p", path])
            braveOutput = output
            braveStatus = .success
            log.append("Políticas verificadas.", level: .success)
        } catch {
            braveOutput = error.localizedDescription
            braveStatus = .error
            log.append("Error verificando: \(error.localizedDescription)", level: .error)
        }
    }

    private func showSource(named: String) {
        do {
            let url = try resolveScript(named)
            sourceText = try String(contentsOf: url, encoding: .utf8)
            sourceTitle = named
        } catch {
            log.append("No se pudo leer \(named): \(error.localizedDescription)", level: .error)
        }
    }

    private var sourceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(sourceTitle).font(.headline)
                Spacer()
                Button("Cerrar") { sourceText = nil }
            }
            ScrollView {
                Text(sourceText ?? "")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .background(Theme.bgDark)
            .cornerRadius(8)
            .frame(width: 720, height: 480)
        }
        .padding(20)
        .background(Theme.bgCard)
    }
}

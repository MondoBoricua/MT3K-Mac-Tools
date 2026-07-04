import SwiftUI

struct OutputBox: View {
    let text: String
    let status: OutputStatus

    private var borderColor: Color {
        switch status {
        case .success: return Theme.green
        case .error: return Theme.accent
        case .info: return Theme.blue
        case .none: return Theme.border
        }
    }

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxHeight: 200)
        .background(Theme.bgDark)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(borderColor))
    }
}

struct ActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var outline: Bool = false
    let busy: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).tint(outline ? Theme.amber : .white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 14)
            .foregroundColor(outline ? Theme.textSecondary : .white)
            .background(outline ? Color.clear : color)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(outline ? Theme.border : Color.clear, lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
        .opacity((disabled && !busy) ? 0.5 : 1.0)
    }
}

struct BadgePill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .overlay(Capsule().strokeBorder(color.opacity(0.3)))
            .clipShape(Capsule())
    }
}

struct PreflightRow: View {
    let ok: Bool
    let title: String
    let detail: String
    let actionLabel: String?
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(ok ? Theme.green : Theme.amber)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail)
                    .foregroundColor(Theme.textSecondary)
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer()
            if let label = actionLabel {
                Button(label, action: action).disabled(disabled)
            }
        }
    }
}

struct InstallRow: View {
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var brew: BrewState
    @EnvironmentObject var installer: InstallCoordinator

    let item: CatalogItem
    let isSelected: Bool
    let selectionEnabled: Bool
    let onSelectionChange: (Bool) -> Void
    @AppStorage("installBehavior") private var installBehavior = "ask"
    @AppStorage("confirmSecurityTools") private var confirmSecurityTools = true
    @State private var replacePrompt: ReplacePrompt? = nil
    @State private var securityPrompt = false

    struct ReplacePrompt: Identifiable {
        let id = UUID()
        let appName: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    rowIdentity
                        .gridColumnAlignment(.leading)
                    methodBadge
                        .gridColumnAlignment(.trailing)
                    installButton
                        .gridColumnAlignment(.trailing)
                }
            }
            if let detailText {
                Text(detailText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(detailColor)
                    .padding(.leading, 44)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .alert(
            "Ya existe en /Applications",
            isPresented: Binding(
                get: { replacePrompt != nil },
                set: { if !$0 { replacePrompt = nil } }
            ),
            presenting: replacePrompt
        ) { _ in
            Button("Reemplazar", role: .destructive) {
                Task { await installer.install(item, force: true, log: log) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { ctx in
            Text("Ya hay un \(ctx.appName) en /Applications. brew se negará a sobreescribirlo. ¿Querés que pase --force y lo reemplace? (los datos personales/cuenta no se tocan — vivo en otra carpeta.)")
        }
        .alert("Instalar herramienta de ciberseguridad", isPresented: $securityPrompt) {
            Button("Instalar") {
                proceedInstallTap()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("\(item.name) puede instalar herramientas de red, auditoría o pentesting. Úsala solo en sistemas donde tengas autorización.")
        }
    }

    private var rowIdentity: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onSelectionChange($0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            .disabled(!selectionEnabled || status.isBusy)

            Image(systemName: item.symbol)
                .font(.system(size: 22))
                .foregroundColor(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.name).bold()
                        .lineLimit(1)
                    rowBadges
                }
                if let liveLine {
                    Text(liveLine)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(item.description)
                        .foregroundColor(Theme.textSecondary)
                        .font(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBadges: some View {
        HStack(spacing: 6) {
            if item.requiresAdminInstall {
                BadgePill(text: "Terminal", color: Theme.amber)
            }
            if isOutdated {
                BadgePill(text: "Update", color: Theme.orange)
            }
            if canAdoptIntoBrew {
                BadgePill(text: "Brew disponible", color: Theme.blue)
            }
        }
    }

    private var methodBadge: some View {
        Text(item.install.label)
            .font(.system(size: 10, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.border.opacity(0.6))
            .foregroundColor(Theme.textSecondary)
            .cornerRadius(4)
    }

    private var installButton: some View {
        Button {
            if canAdoptIntoBrew && isSelected {
                Task {
                    log.append("\(item.name) existe en /Applications; instalando con --force para gestionarlo vía Brew.", level: .info)
                    await installer.install(item, force: true, log: log)
                    await brew.refresh()
                }
            } else if isOutdated {
                Task {
                    await installer.update(item, log: log)
                    await brew.refresh()
                }
            } else if isKnownInstalled, let appName = item.appName {
                openInstalledApp(appName)
            } else {
                onInstallTap()
            }
        } label: {
            StatusActionLabel(kind: actionKind)
        }
        .buttonStyle(.plain)
        .disabled(status.isBusy || !canInstall)
    }

    private var actionKind: StatusActionLabel.Kind {
        if status.isBusy {
            switch status {
            case .terminal:
                return .terminal(buttonTitle)
            default:
                return .busy(buttonTitle)
            }
        }
        if status.succeeded { return .success("Listo") }
        if canAdoptIntoBrew && isSelected { return .installViaBrew }
        if isOutdated { return .update }
        if isKnownInstalled {
            return brew.isInstalled(item.install) ? .openBrew : .openApp
        }
        return .install
    }

    private var status: InstallCoordinator.Status {
        installer.status(for: item)
    }

    private var statusColor: Color {
        switch status {
        case .success: return Theme.green
        case .failed: return Theme.amber
        case .queued, .running, .terminal: return Theme.blue
        case .idle: return appExists ? Theme.green : Theme.blue
        }
    }

    private var buttonTitle: String {
        switch status {
        case .queued: return "En cola"
        case .terminal: return "Terminal"
        case .running(let phase, _): return phase.isEmpty ? "Instalando" : phase
        default: return "Instalando"
        }
    }

    private var liveLine: String? {
        switch status {
        case .running(_, let line): return line.isEmpty ? nil : line
        case .terminal(let message): return message
        case .queued: return "Esperando turno en la cola"
        default: return nil
        }
    }

    private var detailText: String? {
        switch status {
        case .success(let message), .failed(let message), .terminal(let message):
            return message.isEmpty ? nil : message
        default:
            return nil
        }
    }

    private var detailColor: Color {
        switch status {
        case .success: return Theme.green
        case .failed, .terminal: return Theme.amber
        default: return Theme.textSecondary
        }
    }

    private var appExists: Bool {
        guard let appName = item.appName else { return false }
        return FileManager.default.fileExists(atPath: "/Applications/\(appName)")
    }

    private var isOutdated: Bool {
        brew.isOutdated(item.install)
    }

    private var isKnownInstalled: Bool {
        if brew.isInstalled(item.install) { return true }
        return appExists
    }

    private var canAdoptIntoBrew: Bool {
        appExists && item.install.brewPackageName != nil && !brew.isInstalled(item.install)
    }

    private var installStateTitle: String {
        if brew.isInstalled(item.install) { return "En Brew" }
        return "Instalado"
    }

    private func onInstallTap() {
        if item.category == .cybersec && confirmSecurityTools {
            securityPrompt = true
            return
        }
        proceedInstallTap()
    }

    private func proceedInstallTap() {
        let installsToApplications: Bool = {
            switch item.install {
            case .brewCask, .dmg, .githubLatest: return true
            default: return false
            }
        }()
        if installsToApplications,
           let appName = item.appName,
           FileManager.default.fileExists(atPath: "/Applications/\(appName)") {
            switch installBehavior {
            case "skip":
                log.append("\(item.name) ya existe; omitido por Settings.", level: .info)
            case "force":
                Task { await installer.install(item, force: true, log: log) }
            default:
                replacePrompt = .init(appName: appName)
            }
        } else {
            Task { await installer.install(item, force: false, log: log) }
        }
    }

    private func openInstalledApp(_ appName: String) {
        let url = URL(fileURLWithPath: "/Applications/\(appName)")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            Task { @MainActor in
                if let error {
                    log.append("No se pudo abrir \(item.name): \(error.localizedDescription)", level: .error)
                } else {
                    log.append("Abriendo \(item.name)...", level: .info)
                }
            }
        }
    }

    private var canInstall: Bool {
        switch item.install {
        case .brewCask, .brewFormula, .brewTap: return brew.brewInstalled
        case .npm: return brew.nodeInstalled
        case .dmg, .githubLatest: return true   // curl + hdiutil son built-in
        }
    }
}

struct StatusActionLabel: View {
    enum Kind {
        case install
        case installViaBrew
        case update
        case openBrew
        case openApp
        case success(String)
        case terminal(String)
        case busy(String)
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 7) {
            if case .busy = kind {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 128, height: subtitle == nil ? 32 : 38)
        .foregroundColor(foreground)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var title: String {
        switch kind {
        case .install: return "Instalar"
        case .installViaBrew: return "Instalar"
        case .update: return "Actualizar"
        case .openBrew, .openApp: return "Open"
        case .success(let text), .terminal(let text), .busy(let text): return text
        }
    }

    private var subtitle: String? {
        switch kind {
        case .installViaBrew: return "vía Brew"
        case .openBrew: return "vía Brew"
        case .openApp: return "en /Applications"
        default: return nil
        }
    }

    private var systemImage: String {
        switch kind {
        case .install, .installViaBrew: return "arrow.down.circle.fill"
        case .update: return "arrow.triangle.2.circlepath"
        case .openBrew, .openApp: return "arrow.up.right.square.fill"
        case .success: return "checkmark"
        case .terminal: return "apple.terminal.fill"
        case .busy: return "circle"
        }
    }

    private var baseColor: Color {
        switch kind {
        case .install, .installViaBrew: return Theme.blue
        case .update: return Theme.orange
        case .openBrew, .success: return Theme.green
        case .openApp: return Theme.textSecondary
        case .terminal, .busy: return Theme.amber
        }
    }

    private var foreground: Color {
        switch kind {
        case .install, .installViaBrew:
            return .white
        default:
            return baseColor
        }
    }

    private var background: Color {
        switch kind {
        case .install, .installViaBrew:
            return baseColor
        default:
            return baseColor.opacity(0.16)
        }
    }

    private var border: Color {
        switch kind {
        case .install, .installViaBrew:
            return Color.clear
        default:
            return baseColor.opacity(0.35)
        }
    }
}

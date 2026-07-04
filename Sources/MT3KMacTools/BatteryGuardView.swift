import AppKit
import Darwin
import Foundation
import SwiftUI

struct BatteryReading {
    var percent: Int = 0
    var chargingState: String = "unknown"
    var powerSource: String = "unknown"
    var hasBattery = false

    var adapterConnected: Bool {
        powerSource.localizedCaseInsensitiveContains("AC")
    }
}

struct BatterySMCProbe {
    var chargeInhibit = false
    var forceDischarge = false
    var bclm = false
    var chargingInhibited = false
    var forceDischarging = false
    var bclmValue: String = "unavailable"

    var hasModernControl: Bool { chargeInhibit }
}

@MainActor
final class BatteryGuardState: ObservableObject {
    private let daemonPath = "/Library/PrivilegedHelperTools/com.mt3k.mac-tools.battery-helper"
    private let daemonPlist = "/Library/LaunchDaemons/com.mt3k.mac-tools.battery-helper.plist"
    private let daemonSocket = "/var/run/com.mt3k.mac-tools.battery-helper.sock"

    @Published var loading = false
    @Published var busy = false
    @Published var reading = BatteryReading()
    @Published var probe = BatterySMCProbe()
    @Published var status = "Battery Guard listo."
    @Published var lastAction = "Sin acciones todavía."
    @Published var helperAvailable = false
    @Published var daemonInstalled = false
    @Published var daemonReachable = false
    @Published var topUpActive = false
    @Published var output = ""

    private var helperURL: URL? {
        if let bundled = Bundle.main.url(forResource: "mt3k-battery-helper", withExtension: nil) {
            return bundled
        }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        var dir = executable.deletingLastPathComponent()
        for _ in 0..<8 {
            let candidates = [
                dir.appendingPathComponent("mt3k-battery-helper"),
                dir.appendingPathComponent(".build/debug/mt3k-battery-helper"),
                dir.appendingPathComponent(".build/release/mt3k-battery-helper"),
                dir.appendingPathComponent(".build/arm64-apple-macosx/debug/mt3k-battery-helper"),
                dir.appendingPathComponent(".build/arm64-apple-macosx/release/mt3k-battery-helper")
            ]
            if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
                return found
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    func refresh() async {
        loading = true
        defer { loading = false }

        async let battery = readBattery()
        async let smcProbe = readProbe()
        reading = await battery
        probe = await smcProbe
        helperAvailable = helperURL != nil
        daemonInstalled = FileManager.default.isExecutableFile(atPath: daemonPath)
        daemonReachable = await pingDaemon()
        if daemonReachable {
            // Un daemon viejo responde config get sin topUp → contains() da false. OK.
            let config = (try? await runDaemonCommand(args: ["config", "get"])) ?? ""
            topUpActive = config.contains("topUp=true")
        } else {
            topUpActive = false
        }
        if !reading.hasBattery {
            status = "No se detectó batería interna."
        } else if !helperAvailable {
            status = "Helper SMC no encontrado en el bundle."
        } else if !daemonReachable {
            status = daemonInstalled ? "Helper permanente instalado, pero no responde. Reinstálalo." : "Instala el helper permanente para controlar SMC sin pedir password cada vez."
        } else if probe.hasModernControl {
            status = "Control SMC disponible para pausar/reanudar carga."
        } else if probe.bclm {
            status = "Control legacy Intel disponible vía BCLM."
        } else {
            status = "Este Mac no expone llaves SMC compatibles para control nativo."
        }
    }

    func startGuard(limit: Int, resumeBelow: Int) async -> Bool {
        guard reading.hasBattery else {
            status = "No hay batería interna para controlar."
            return false
        }
        guard helperAvailable else {
            status = "No encontré mt3k-battery-helper en el bundle."
            return false
        }
        guard daemonReachable else {
            status = "Instala el helper permanente antes de activar Guard."
            return false
        }
        let result = await evaluateGuard(limit: limit, resumeBelow: resumeBelow, reason: "start")
        if result {
            status = "Battery Guard activo con límite \(limit)%."
            // Hand the limit to the daemon so it keeps enforcing even when the app is closed.
            _ = try? await runDaemonCommand(args: ["config", "set", "1", "\(limit)", "\(resumeBelow)"])
        }
        return result
    }

    /// "Carga completa por hoy": suspende el límite hasta 100% o desconexión.
    /// El daemon rearma el guard solo; requiere el helper con soporte de `topup`.
    func startTopUp() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await runDaemonCommand(args: ["topup", "start"])
            topUpActive = true
            status = "Top-up activo: cargando a 100%. El límite se rearma solo al llegar o al desconectar."
            lastAction = "Top-up iniciado."
        } catch {
            // Daemon anterior sin el comando `topup` → reinstalar helper.
            status = "No se pudo iniciar el top-up. Si el helper es anterior, usa \"Reinstalar helper\". (\(error.localizedDescription))"
        }
    }

    func stopTopUp() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await runDaemonCommand(args: ["topup", "stop"])
            topUpActive = false
            status = "Top-up cancelado; el límite vuelve a aplicar en el próximo ciclo (≤30 s)."
            lastAction = "Top-up cancelado."
        } catch {
            status = "No se pudo cancelar el top-up: \(error.localizedDescription)"
        }
    }

    func stopGuard() async {
        busy = true
        defer { busy = false }
        do {
            // Tell the daemon to stop autonomous enforcement before clearing SMC state.
            _ = try? await runDaemonCommand(args: ["config", "set", "0", "100", "95"])
            output = try await runDaemonCommand(args: ["reset"])
            lastAction = "Guard detenido y SMC reseteado."
            status = "Carga reanudada."
            await refresh()
        } catch {
            status = "No se pudo resetear Battery Guard: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func evaluateGuard(limit: Int, resumeBelow: Int, reason: String) async -> Bool {
        guard reading.hasBattery, helperAvailable else { return false }
        guard daemonReachable else {
            status = "Battery Guard activo, pero el helper permanente no responde."
            return false
        }

        busy = true
        defer { busy = false }

        await refresh()

        do {
            if probe.hasModernControl {
                if reading.adapterConnected && reading.percent >= limit && !probe.chargingInhibited {
                    output = try await runDaemonCommand(args: ["inhibit", "on"])
                    lastAction = "Carga pausada en \(reading.percent)% (\(reason))."
                } else if (!reading.adapterConnected || reading.percent <= resumeBelow) && probe.chargingInhibited {
                    output = try await runDaemonCommand(args: ["inhibit", "off"])
                    lastAction = "Carga reanudada en \(reading.percent)% (\(reason))."
                } else {
                    lastAction = "Sin cambio: \(reading.percent)% · \(reading.chargingState)."
                }
                await refresh()
                return true
            }

            if probe.bclm {
                output = try await runDaemonCommand(args: ["bclm", "set", "\(limit)"])
                lastAction = "BCLM ajustado a \(limit)%."
                await refresh()
                return true
            }

            status = "SMC no compatible con control de carga en este equipo."
            return false
        } catch {
            status = "Battery Guard falló: \(error.localizedDescription)"
            return false
        }
    }

    func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func installDaemon(auth: AdminAuth) async {
        busy = true
        defer { busy = false }
        guard let helperURL else {
            status = "No encontré el helper bundled."
            return
        }
        do {
            try auth.acquire(prompt: "MT3K instalará un helper permanente para controlar la batería sin pedir password cada vez.")
            let script = try writeDaemonInstallScript()
            output = try await auth.runPrivileged(scriptPath: script.path, args: [helperURL.path])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lastAction = "Helper permanente instalado."
            await refresh()
        } catch {
            status = "No se pudo instalar el helper: \(error.localizedDescription)"
        }
    }

    func uninstallDaemon(auth: AdminAuth) async {
        busy = true
        defer { busy = false }
        do {
            try auth.acquire(prompt: "MT3K removerá el helper permanente de batería.")
            let script = try writeDaemonUninstallScript()
            output = try await auth.runPrivileged(scriptPath: script.path)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lastAction = "Helper permanente removido."
            await refresh()
        } catch {
            status = "No se pudo remover el helper: \(error.localizedDescription)"
        }
    }

    private func readProbe() async -> BatterySMCProbe {
        if let raw = try? await runDaemonCommand(args: ["probe"]) {
            return parseProbe(raw)
        }
        guard let helperURL else { return BatterySMCProbe() }
        do {
            let raw = try await runShell(executable: helperURL.path, args: ["probe"])
            return parseProbe(raw)
        } catch {
            return BatterySMCProbe()
        }
    }

    private func pingDaemon() async -> Bool {
        (try? await runDaemonCommand(args: ["probe"])) != nil
    }

    private func runDaemonCommand(args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) { [daemonSocket] in
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                throw NSError(domain: "MT3K", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear socket local"])
            }
            defer { close(fd) }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let encoded = Array(daemonSocket.utf8CString)
            guard encoded.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                throw NSError(domain: "MT3K", code: 2, userInfo: [NSLocalizedDescriptionKey: "Socket path demasiado largo"])
            }
            withUnsafeMutableBytes(of: &address.sun_path) { buffer in
                for (index, byte) in encoded.enumerated() {
                    buffer[index] = UInt8(bitPattern: byte)
                }
            }

            let connected = withUnsafePointer(to: &address) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connected == 0 else {
                throw NSError(domain: "MT3K", code: 3, userInfo: [NSLocalizedDescriptionKey: "Helper permanente no responde"])
            }

            let request = args.joined(separator: " ") + "\n"
            _ = request.withCString { ptr in
                Darwin.write(fd, ptr, strlen(ptr))
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.hasPrefix("ok\n") {
                return String(raw.dropFirst(3))
            }
            if raw == "ok" { return "" }
            if raw.hasPrefix("error\n") {
                throw NSError(domain: "MT3K", code: 4, userInfo: [NSLocalizedDescriptionKey: String(raw.dropFirst(6))])
            }
            throw NSError(domain: "MT3K", code: 5, userInfo: [NSLocalizedDescriptionKey: raw.isEmpty ? "Respuesta vacía del helper" : raw])
        }.value
    }

    private func readBattery() async -> BatteryReading {
        do {
            let raw = try await runShell(executable: "/usr/bin/pmset", args: ["-g", "batt"])
            return Self.parseBattery(raw)
        } catch {
            return BatteryReading()
        }
    }

    nonisolated static func parseBattery(_ raw: String) -> BatteryReading {
        var result = BatteryReading()
        if let source = raw.range(of: #"Now drawing from '([^']+)'"#, options: .regularExpression) {
            result.powerSource = String(raw[source])
                .replacingOccurrences(of: "Now drawing from '", with: "")
                .replacingOccurrences(of: "'", with: "")
        }

        guard let percentRange = raw.range(of: #"(\d+)%"#, options: .regularExpression) else {
            return result
        }

        result.hasBattery = true
        result.percent = Int(raw[percentRange].dropLast()) ?? 0
        let lower = raw.lowercased()
        // "discharging" contiene "charging" como substring: hay que chequearlo primero
        // o la rama nunca se alcanza y el popover dice "cargando" estando en batería.
        if lower.contains("not charging") {
            result.chargingState = "not charging"
        } else if lower.contains("finishing charge") {
            result.chargingState = "finishing charge"
        } else if lower.contains("discharging") {
            result.chargingState = "discharging"
        } else if lower.contains("charging") {
            result.chargingState = "charging"
        } else {
            result.chargingState = "idle"
        }
        return result
    }

    private func parseProbe(_ raw: String) -> BatterySMCProbe {
        var probe = BatterySMCProbe()
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch parts[0] {
            case "chargeInhibit": probe.chargeInhibit = value == "true"
            case "forceDischarge": probe.forceDischarge = value == "true"
            case "bclm": probe.bclm = value == "true"
            case "chargingInhibited": probe.chargingInhibited = value == "true"
            case "forceDischarging": probe.forceDischarging = value == "true"
            case "bclmValue": probe.bclmValue = value
            default: break
            }
        }
        return probe
    }

    private func writeDaemonInstallScript() throws -> URL {
        let script = """
        #!/bin/zsh
        set -euo pipefail
        SRC="$1"
        LABEL="com.mt3k.mac-tools.battery-helper"
        DEST="/Library/PrivilegedHelperTools/${LABEL}"
        PLIST="/Library/LaunchDaemons/${LABEL}.plist"
        SOCK="/var/run/${LABEL}.sock"

        /bin/mkdir -p /Library/PrivilegedHelperTools
        /bin/cp "$SRC" "$DEST"
        /usr/sbin/chown root:wheel "$DEST"
        /bin/chmod 755 "$DEST"

        /bin/cat > "$PLIST" <<PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>${LABEL}</string>
          <key>ProgramArguments</key>
          <array>
            <string>${DEST}</string>
            <string>--daemon</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>/var/log/${LABEL}.log</string>
          <key>StandardErrorPath</key><string>/var/log/${LABEL}.err</string>
        </dict>
        </plist>
        PLIST
        /usr/sbin/chown root:wheel "$PLIST"
        /bin/chmod 644 "$PLIST"

        /bin/launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
        /bin/rm -f "$SOCK"
        /bin/launchctl bootstrap system "$PLIST"
        /bin/launchctl enable system/${LABEL}
        echo "Helper permanente instalado."
        """
        return try writeTempScript(script, name: "install-battery-helper")
    }

    private func writeDaemonUninstallScript() throws -> URL {
        let script = """
        #!/bin/zsh
        set -euo pipefail
        LABEL="com.mt3k.mac-tools.battery-helper"
        DEST="/Library/PrivilegedHelperTools/${LABEL}"
        PLIST="/Library/LaunchDaemons/${LABEL}.plist"
        SOCK="/var/run/${LABEL}.sock"
        /bin/launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
        /bin/rm -f "$SOCK" "$DEST" "$PLIST"
        echo "Helper permanente removido."
        """
        return try writeTempScript(script, name: "uninstall-battery-helper")
    }

    private func writeTempScript(_ script: String, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mt3k-\(name)-\(UUID().uuidString).sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

struct BatteryGuardView: View {
    @EnvironmentObject var auth: AdminAuth
    @EnvironmentObject var state: BatteryGuardState
    @AppStorage("batteryGuardEnabled") private var guardEnabled = false
    @AppStorage("batteryGuardLimit") private var limit = 80.0
    @AppStorage("batteryGuardResumeBelow") private var resumeBelow = 75.0
    @State private var suppressNextStop = false
    @State private var showAdvancedActions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                controlPanel
                statePanel
                if !state.output.isEmpty {
                    OutputBox(text: state.output, status: .info)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            await state.refresh()
        }
        .onChange(of: guardEnabled) { _, enabled in
            Task {
                if enabled {
                    let started = await state.startGuard(limit: Int(limit), resumeBelow: Int(resumeBelow))
                    if !started {
                        suppressNextStop = true
                        guardEnabled = false
                    }
                } else {
                    if suppressNextStop {
                        suppressNextStop = false
                        return
                    }
                    await state.stopGuard()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(guardEnabled ? Theme.green : Theme.amber)
                .frame(width: 52, height: 52)
                .background((guardEnabled ? Theme.green : Theme.amber).opacity(0.14))
                .clipShape(.rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 6) {
                Text("BATTERY").font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Theme.accent)
                Text("MT3K Battery Guard").font(.title2).bold()
                Text("Límite de carga estilo AlDente usando control SMC cuando el equipo lo permite, con reset manual siempre visible.")
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            SystemActionButton(title: "Refrescar", symbol: "arrow.clockwise", color: Theme.blue, busy: state.loading) {
                Task { await state.refresh() }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .overlay(Rectangle().frame(width: 4).foregroundColor(Theme.accent), alignment: .leading)
        .cornerRadius(12)
    }

    private var controlPanel: some View {
        SystemPanel(title: "Charge Limit", symbol: "slider.horizontal.3") {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.reading.percent)%")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("\(state.reading.powerSource) · \(state.reading.chargingState)")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Toggle(isOn: $guardEnabled) {
                        Text(guardEnabled ? "Guard ON" : "Guard OFF")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .toggleStyle(.switch)
                    .disabled(state.busy || !state.helperAvailable || !state.reading.hasBattery)

                    HStack {
                        BadgePill(text: state.probe.hasModernControl ? "Control compatible" : (state.probe.bclm ? "Límite legacy" : "Sin control"), color: state.probe.hasModernControl || state.probe.bclm ? Theme.green : Theme.amber)
                        BadgePill(text: state.daemonReachable ? "Helper activo" : "Helper requerido", color: state.daemonReachable ? Theme.green : Theme.amber)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Límite")
                    Slider(value: $limit, in: 50...100, step: 1)
                    Text("\(Int(limit))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("Reanudar bajo")
                    Slider(value: $resumeBelow, in: 40...95, step: 1)
                    Text("\(Int(resumeBelow))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Text("Deja Apple Charge Limit en 100% y Optimized Battery Charging apagado para evitar que macOS compita con MT3K.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                BatteryActionCard(title: "Aplicar ahora", detail: "Evalúa porcentaje y escribe SMC si hace falta.", symbol: "bolt.fill", color: Theme.green, busy: state.busy) {
                    Task {
                        guardEnabled = await state.startGuard(limit: Int(limit), resumeBelow: Int(resumeBelow))
                    }
                }
                if guardEnabled && state.daemonReachable {
                    BatteryActionCard(
                        title: state.topUpActive ? "Cancelar top-up" : "Carga completa por hoy",
                        detail: state.topUpActive
                            ? "Cargando a 100%; el límite se rearma solo al llegar o al desconectar."
                            : "Suspende el límite hasta 100% o hasta desconectar el charger; luego el guard se rearma solo.",
                        symbol: state.topUpActive ? "xmark.circle.fill" : "battery.100percent.bolt",
                        color: state.topUpActive ? Theme.amber : Theme.blue,
                        busy: state.busy
                    ) {
                        Task {
                            if state.topUpActive {
                                await state.stopTopUp()
                            } else {
                                await state.startTopUp()
                            }
                        }
                    }
                }
                BatteryActionCard(title: "Battery Settings", detail: "Abre el panel nativo de Apple para Optimized Battery Charging.", symbol: "gearshape.fill", color: Theme.blue, busy: false) {
                    state.openBatterySettings()
                }
            }

            DisclosureGroup(isExpanded: $showAdvancedActions) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    BatteryActionCard(title: "Reset de carga", detail: "Reanuda carga, apaga descarga forzada y restaura el límite legacy si existe.", symbol: "arrow.uturn.backward.circle.fill", color: Theme.amber, busy: state.busy) {
                        Task {
                            guardEnabled = false
                            await state.stopGuard()
                        }
                    }
                    BatteryActionCard(
                        title: state.daemonReachable ? "Reinstalar helper" : "Instalar helper",
                        detail: state.daemonReachable ? "Actualiza el daemon permanente firmado." : "Pide password una vez y deja el daemon root activo.",
                        symbol: "lock.shield.fill",
                        color: Theme.green,
                        busy: state.busy
                    ) {
                        Task { await state.installDaemon(auth: auth) }
                    }
                    if state.daemonInstalled {
                        BatteryActionCard(title: "Remover helper", detail: "Quita LaunchDaemon y helper permanente.", symbol: "trash.fill", color: Theme.sevCritical, busy: state.busy) {
                            Task { await state.uninstallDaemon(auth: auth) }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Avanzado y mantenimiento", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var statePanel: some View {
        SystemPanel(title: "Estado", symbol: "waveform.path.ecg") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                BatteryMetricCard(title: "Batería", value: state.reading.hasBattery ? "\(state.reading.percent)%" : "No data", detail: state.reading.chargingState, color: Theme.green, symbol: "battery.75percent")
                BatteryMetricCard(title: "Control de carga", value: state.probe.chargeInhibit ? "OK" : "No", detail: state.probe.chargingInhibited ? "Carga pausada" : "Carga permitida", color: state.probe.chargeInhibit ? Theme.green : Theme.amber, symbol: "bolt.slash.fill")
                BatteryMetricCard(title: "Descarga forzada", value: state.probe.forceDischarge ? "OK" : "No", detail: state.probe.forceDischarging ? "Activa" : "Apagada", color: state.probe.forceDischarge ? Theme.blue : Theme.textSecondary, symbol: "minus.plus.batteryblock.fill")
                BatteryMetricCard(title: "Límite legacy", value: state.probe.bclm ? "\(state.probe.bclmValue)%" : "No aplica", detail: state.probe.bclm ? "Intel antiguo" : "Apple Silicon usa control SMC", color: state.probe.bclm ? Theme.green : Theme.textSecondary, symbol: "cpu.fill")
            }

            Text(state.status)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            Text(state.lastAction)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }

}

private struct BatteryMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundColor(Theme.textSecondary)
                Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(color)
                Text(detail).font(.caption2).foregroundColor(Theme.textSecondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(color.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.25)))
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct BatteryActionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                if busy {
                    ProgressView().controlSize(.small).tint(color)
                        .frame(width: 26)
                } else {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundColor(color)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .frame(height: 34, alignment: .topLeading)
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(height: 42, alignment: .topLeading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 108, maxHeight: 108, alignment: .topLeading)
            .background(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.30)))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

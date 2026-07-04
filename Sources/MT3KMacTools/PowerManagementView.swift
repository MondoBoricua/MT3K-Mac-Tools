import AppKit
import Darwin
import Foundation
import SwiftUI

enum MT3KCaffeinate {
    static let pidFile = "/tmp/mt3k-caffeinate.pid"
    static let modeFile = "/tmp/mt3k-caffeinate.mode"
    static let logFile = "/tmp/mt3k-caffeinate.log"

    static var mode: String {
        (try? String(contentsOfFile: modeFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func activePID() -> Int32? {
        guard let raw = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else {
            cleanup()
            return nil
        }
        return pid
    }

    static func start(args: [String], mode: String) throws -> Int32 {
        if let pid = activePID() {
            _ = kill(pid, SIGTERM)
            cleanup()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = args

        let logURL = URL(fileURLWithPath: logFile)
        FileManager.default.createFile(atPath: logFile, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        try? logHandle.close()

        let pid = process.processIdentifier
        try "\(pid)\n".write(toFile: pidFile, atomically: true, encoding: .utf8)
        try "\(mode)\n".write(toFile: modeFile, atomically: true, encoding: .utf8)
        return pid
    }

    static func stop() -> Int32? {
        guard let pid = activePID() else {
            cleanup()
            return nil
        }
        _ = kill(pid, SIGTERM)
        cleanup()
        return pid
    }

    static func cleanup() {
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: modeFile)
    }
}

@MainActor
final class PowerManagementState: ObservableObject {
    @Published var loading = false
    @Published var mt3kCaffeinatePID: Int32?
    @Published var externalCaffeinatePIDs: [Int32] = []
    @Published var assertions = ""
    @Published var customProfile = ""
    @Published var externalDisks = ""
    @Published var statusMessage = ""

    var mt3kMode: String {
        MT3KCaffeinate.mode
    }

    var isMT3KActive: Bool { mt3kCaffeinatePID != nil }

    func refresh() async {
        loading = true
        defer { loading = false }

        mt3kCaffeinatePID = MT3KCaffeinate.activePID()
        externalCaffeinatePIDs = await readAllCaffeinatePIDs().filter { $0 != mt3kCaffeinatePID }

        async let assertionOutput = shell("/usr/bin/pmset", ["-g", "assertions"])
        async let customOutput = shell("/usr/bin/pmset", ["-g", "custom"])
        async let diskOutput = shell("/usr/sbin/diskutil", ["list", "external"])

        assertions = await assertionOutput
        customProfile = await customOutput
        externalDisks = await diskOutput
    }

    func startOLEDMode() async {
        await startCaffeinate(args: ["-i", "-m", "-s"], mode: "Keep USB Alive · pantalla puede apagarse")
    }

    func startCaffeineMode() async {
        await startCaffeinate(args: ["-d", "-i", "-m", "-s", "-u"], mode: "Caffeine agresivo · pantalla despierta")
    }

    func toggleAggressiveCaffeine() async {
        if MT3KCaffeinate.activePID() != nil {
            await stopMT3KCaffeinate()
        } else {
            await startCaffeineMode()
        }
    }

    func stopMT3KCaffeinate() async {
        guard let pid = MT3KCaffeinate.stop() else {
            statusMessage = "No hay caffeinate de MT3K activo."
            await refresh()
            return
        }
        statusMessage = "Caffeinate detenido (PID \(pid))."
        await refresh()
    }

    func displayOffNow() async {
        _ = await shell("/usr/bin/pmset", ["displaysleepnow"])
        statusMessage = "Pantalla apagada por pmset displaysleepnow."
    }

    func openOLEDPowerProfile() {
        openTerminalCommand(
            """
            echo "Aplicando perfil OLED/USB en corriente..."
            sudo pmset -c sleep 0 displaysleep 2 disksleep 0 powernap 0
            echo
            echo "Perfil actual:"
            pmset -g custom
            """,
            title: "Install OLED USB Power Profile"
        )
    }

    func openRestorePowerProfile() {
        openTerminalCommand(
            """
            echo "Restaurando perfil normal en corriente..."
            sudo pmset -c sleep 15 displaysleep 10 disksleep 10 powernap 1
            echo
            echo "Perfil actual:"
            pmset -g custom
            """,
            title: "Restore Normal Power Profile"
        )
    }

    func openBatteryPowerProfile() {
        openTerminalCommand(
            """
            echo "Aplicando perfil OLED/USB en batería..."
            echo "Aviso: esto puede drenar la batería si dejas la Mac desconectada."
            sudo pmset -b sleep 0 displaysleep 2 disksleep 0 powernap 0
            echo
            echo "Perfil actual:"
            pmset -g custom
            """,
            title: "Install Battery OLED USB Power Profile"
        )
    }

    private func startCaffeinate(args: [String], mode: String) async {
        do {
            let pid = try MT3KCaffeinate.start(args: args, mode: mode)
            statusMessage = "\(mode) activo (PID \(pid))."
        } catch {
            statusMessage = "No se pudo arrancar caffeinate: \(error.localizedDescription)"
        }
        await refresh()
    }

    private func readAllCaffeinatePIDs() async -> [Int32] {
        let raw = await shell("/usr/bin/pgrep", ["-x", "caffeinate"])
        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func shell(_ executable: String, _ args: [String]) async -> String {
        (try? await runShell(executable: executable, args: args))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func openTerminalCommand(_ command: String, title: String) {
        do {
            let script = """
            #!/bin/zsh
            set -e
            \(command)
            echo
            echo "Listo. Puedes cerrar esta ventana."
            read -k 1 "?Presiona cualquier tecla para cerrar..."
            """
            let safeTitle = title.replacingOccurrences(of: " ", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mt3k-\(safeTitle)-\(UUID().uuidString).command")
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try openInTerminal(scriptPath: url.path)
            statusMessage = "Abriendo Terminal: \(title)."
        } catch {
            statusMessage = "No se pudo abrir Terminal: \(error.localizedDescription)"
        }
    }
}

struct PowerManagementSection: View {
    @ObservedObject var state: PowerManagementState
    @State private var showAssertions = false
    @State private var showProfile = false
    @State private var showDisks = false

    var body: some View {
        SystemPanel(title: "Power / OLED / USB Keep Awake", symbol: "powerplug.fill") {
            statusHeader
            actionGrid
            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            disclosure(title: "Assertions actuales", symbol: "list.clipboard.fill", isOpen: $showAssertions, text: state.assertions)
            disclosure(title: "Perfil pmset permanente", symbol: "slider.horizontal.3", isOpen: $showProfile, text: state.customProfile)
            disclosure(title: "Discos externos", symbol: "externaldrive.fill", isOpen: $showDisks, text: state.externalDisks)
        }
        .task { await state.refresh() }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isMT3KActive ? "bolt.circle.fill" : "moon.zzz.fill")
                .font(.title2)
                .foregroundColor(state.isMT3KActive ? Theme.green : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.isMT3KActive ? "Keep awake activo" : "Sin keep-awake de MT3K")
                    .font(.headline)
                Text(statusDetail)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            SystemActionButton(title: "Refrescar", symbol: "arrow.clockwise", color: Theme.blue, busy: state.loading) {
                Task { await state.refresh() }
            }
            .disabled(state.loading)
        }
    }

    private var statusDetail: String {
        if let pid = state.mt3kCaffeinatePID {
            return "\(state.mt3kMode.isEmpty ? "caffeinate" : state.mt3kMode) · PID \(pid)"
        }
        if state.externalCaffeinatePIDs.isEmpty {
            return "No se detectó caffeinate corriendo."
        }
        return "Hay caffeinate externo: \(state.externalCaffeinatePIDs.map(String.init).joined(separator: ", "))"
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
            PowerActionCard(
                title: "Keep USB Alive",
                detail: "caffeinate -ims. Mantiene sistema/discos despiertos y deja apagar la pantalla.",
                symbol: "externaldrive.connected.to.line.below",
                color: Theme.green
            ) { Task { await state.startOLEDMode() } }

            PowerActionCard(
                title: "Caffeine agresivo",
                detail: "caffeinate -dimsu. Evita sleep y display sleep mientras esté activo.",
                symbol: "cup.and.saucer.fill",
                color: Theme.amber
            ) { Task { await state.startCaffeineMode() } }

            PowerActionCard(
                title: "Stop MT3K Keep Awake",
                detail: "Detiene solo el PID que arrancó esta app; no toca otros caffeinate.",
                symbol: "stop.circle.fill",
                color: Theme.sevCritical
            ) { Task { await state.stopMT3KCaffeinate() } }

            PowerActionCard(
                title: "Display Off",
                detail: "pmset displaysleepnow. Ideal para OLED mientras Keep USB Alive corre.",
                symbol: "display",
                color: Theme.blue
            ) { Task { await state.displayOffNow() } }

            PowerActionCard(
                title: "Install OLED/USB Power Profile",
                detail: "sudo pmset -c sleep 0 displaysleep 2 disksleep 0 powernap 0",
                symbol: "bolt.shield.fill",
                color: Theme.green
            ) { state.openOLEDPowerProfile() }

            PowerActionCard(
                title: "Restore Normal Power Profile",
                detail: "sudo pmset -c sleep 15 displaysleep 10 disksleep 10 powernap 1",
                symbol: "arrow.uturn.backward.circle.fill",
                color: Theme.amber
            ) { state.openRestorePowerProfile() }

            PowerActionCard(
                title: "Battery profile (opcional)",
                detail: "sudo pmset -b sleep 0 displaysleep 2 disksleep 0 powernap 0",
                symbol: "battery.75percent",
                color: Theme.orange
            ) { state.openBatteryPowerProfile() }
        }
    }

    private func disclosure(title: String, symbol: String, isOpen: Binding<Bool>, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                isOpen.wrappedValue.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundColor(Theme.blue)
                    Text(title).font(.caption.bold())
                    Spacer()
                    Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            if isOpen.wrappedValue {
                Text(text.isEmpty ? "Sin datos." : text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.bgDark)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
    }
}

private struct PowerActionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .frame(height: 36, alignment: .topLeading)
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(height: 48, alignment: .topLeading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
            .background(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.30)))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

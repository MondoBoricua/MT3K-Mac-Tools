// Menu bar — popover principal (MenuBarContent).
import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject var bridge: MenuBarBridge
    @EnvironmentObject var loginItem: LoginItemState
    @EnvironmentObject var battery: BatteryGuardState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("batteryGuardEnabled") private var batteryGuardEnabled = false
    @AppStorage("batteryGuardLimit") private var batteryGuardLimit = 80.0
    @AppStorage("batteryGuardResumeBelow") private var batteryGuardResumeBelow = 75.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            ollamaRow
            if bridge.brewOutdatedCount > 0 {
                brewRow
            }
            caffeineRow
            batteryRow
            cpuRow
            ramRow
            diskRow
            gpuRow
            Divider()
            actions
            Divider()
            footer
        }
        .padding(10)
        .frame(width: 280)
        .task {
            async let metrics: Void = bridge.refresh()
            async let bat: Void = battery.refresh()
            _ = await (metrics, bat)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.adjustable.fill").foregroundStyle(Theme.gradient)
            Text("MT3K Mac Tools").bold()
            Spacer()
            Button {
                Task { await bridge.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private var cpuRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu.fill")
                .foregroundColor(cpuColor)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("CPU").font(.caption.bold())
                Text(cpuDetail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var cpuDetail: String {
        var parts = [String(format: "%.0f%% uso", bridge.cpuTotal)]
        if !bridge.cpuTempC.isNaN {
            parts.append("\(Int(bridge.cpuTempC))°C")
        }
        parts.append(String(format: "user %.0f%% · sys %.0f%%", bridge.cpuUser, bridge.cpuSys))
        return parts.joined(separator: " · ")
    }

    private var cpuColor: Color {
        if bridge.cpuTotal > 85 { return .red }
        if bridge.cpuTotal > 65 { return .orange }
        return .green
    }

    private var gpuRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "display")
                .foregroundColor(gpuColor)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("GPU").font(.caption.bold())
                Text(gpuDetail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var gpuDetail: String {
        var parts: [String] = []
        if !bridge.gpuUsagePercent.isNaN {
            parts.append(String(format: "%.0f%% uso", bridge.gpuUsagePercent))
        }
        if !bridge.gpuTempC.isNaN {
            parts.append("temp \(Int(bridge.gpuTempC))°C")
        }
        if !bridge.gpuRendererPercent.isNaN || !bridge.gpuTilerPercent.isNaN {
            parts.append(String(format: "renderer %.0f%% · tiler %.0f%%", bridge.gpuRendererPercent, bridge.gpuTilerPercent))
        }
        if bridge.gpuMemoryGB > 0 {
            parts.append(String(format: "%.1f GB", bridge.gpuMemoryGB))
        }
        return parts.isEmpty ? "Sin datos de GPU" : parts.joined(separator: " · ")
    }

    private var gpuColor: Color {
        if !bridge.gpuUsagePercent.isNaN {
            if bridge.gpuUsagePercent > 85 { return .red }
            if bridge.gpuUsagePercent > 65 { return .orange }
            return .green
        }
        if !bridge.gpuTempC.isNaN {
            if bridge.gpuTempC > 85 { return .red }
            if bridge.gpuTempC > 70 { return .orange }
            return .green
        }
        return .secondary
    }

    private var ramRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip.fill")
                .foregroundColor(.blue)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("RAM").font(.caption.bold())
                Text(ramDetail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var ramDetail: String {
        guard bridge.ramTotalGB > 0 else { return "Sin datos" }
        let usedPercent = (bridge.ramUsedGB / max(bridge.ramTotalGB, 1)) * 100
        return String(format: "%.1f/%.0f GB · %.0f%% usado", bridge.ramUsedGB, bridge.ramTotalGB, usedPercent)
    }

    private var diskRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive.fill")
                .foregroundColor(diskColor)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Disco").font(.caption.bold())
                Text(diskDetail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var diskDetail: String {
        guard bridge.diskTotalGB > 0 else { return "Sin datos" }
        return String(format: "%.0f%% usado · %.0f GB libres", bridge.diskUsedPercent, bridge.diskFreeGB)
    }

    private var diskColor: Color {
        if bridge.diskUsedPercent > 90 { return .red }
        if bridge.diskUsedPercent > 80 { return .orange }
        return .green
    }

    private var caffeineRow: some View {
        HStack(spacing: 10) {
            Image(systemName: bridge.caffeinatePID == nil ? "cup.and.saucer" : "cup.and.saucer.fill")
                .foregroundColor(bridge.caffeinatePID == nil ? .secondary : .orange)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Caffeine").font(.caption.bold())
                Text(caffeineDetail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await bridge.toggleCaffeine() }
            } label: {
                Image(systemName: bridge.caffeinatePID == nil ? "play.fill" : "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private var caffeineDetail: String {
        if let pid = bridge.caffeinatePID {
            let mode = bridge.caffeinateMode.isEmpty ? "Activo" : bridge.caffeinateMode
            return "\(mode) · PID \(pid)"
        }
        return "Apagado"
    }

    private var brewRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .foregroundColor(.orange)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Homebrew").font(.caption.bold())
                Text(bridge.brewOutdatedCount == 1
                     ? "1 paquete con update"
                     : "\(bridge.brewOutdatedCount) paquetes con update")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: openMainWindow) {
                Image(systemName: "arrow.up.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Abrir MT3K Mac Tools para actualizar desde Apps")
        }
    }

    private var batteryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: batterySymbol)
                .foregroundColor(batteryColor)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Batería").font(.caption.bold())
                Text(batteryDetail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if battery.reading.hasBattery, batteryGuardEnabled, battery.daemonReachable {
                Button {
                    Task {
                        if battery.topUpActive {
                            await battery.stopTopUp()
                        } else {
                            await battery.startTopUp()
                        }
                        await battery.refresh()
                    }
                } label: {
                    Image(systemName: battery.topUpActive ? "xmark.circle" : "battery.100percent.bolt")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(battery.busy)
                .help(battery.topUpActive
                      ? "Cancelar top-up (cargando a 100%)"
                      : "Carga completa por hoy: suspende el límite hasta 100% o desconexión")
            }
            if battery.reading.hasBattery {
                Toggle("", isOn: guardBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(battery.busy || !battery.daemonReachable)
                    .help(battery.daemonReachable
                          ? "Battery Guard · límite \(Int(batteryGuardLimit))%"
                          : "Instala el helper permanente en el panel Batería")
            }
        }
    }

    private var batteryDetail: String {
        guard battery.reading.hasBattery else { return "Sin batería interna" }
        var parts = ["\(battery.reading.percent)%"]
        if battery.topUpActive {
            parts.append("top-up a 100%")
        } else if battery.probe.chargingInhibited {
            parts.append("pausado por Guard (\(Int(batteryGuardLimit))%)")
        } else if battery.reading.chargingState.localizedCaseInsensitiveContains("charging")
                    && !battery.reading.chargingState.localizedCaseInsensitiveContains("discharging") {
            parts.append("cargando")
        } else if battery.reading.adapterConnected {
            parts.append("en AC")
        } else {
            parts.append("en batería")
        }
        if bridge.batteryCycles > 0 {
            parts.append("\(bridge.batteryCycles) ciclos")
        }
        return parts.joined(separator: " · ")
    }

    private var batterySymbol: String {
        guard battery.reading.hasBattery else { return "battery.slash" }
        if battery.probe.chargingInhibited { return "bolt.badge.xmark" }
        if battery.reading.adapterConnected { return "battery.100percent.bolt" }
        return "battery.75percent"
    }

    private var batteryColor: Color {
        guard battery.reading.hasBattery else { return .secondary }
        if battery.probe.chargingInhibited { return .teal }
        if battery.reading.percent <= 20 { return .red }
        if battery.reading.adapterConnected { return .green }
        return .secondary
    }

    private var guardBinding: Binding<Bool> {
        Binding(
            get: { batteryGuardEnabled },
            set: { enabled in
                Task { @MainActor in
                    if enabled {
                        let started = await battery.startGuard(
                            limit: Int(batteryGuardLimit),
                            resumeBelow: Int(batteryGuardResumeBelow)
                        )
                        batteryGuardEnabled = started
                    } else {
                        batteryGuardEnabled = false
                        await battery.stopGuard()
                    }
                    await battery.refresh()
                }
            }
        )
    }

    private var ollamaRow: some View {
        HStack(spacing: 10) {
            Image(systemName: bridge.ollamaUp ? "brain.head.profile" : "brain.head.profile")
                .foregroundColor(bridge.ollamaUp ? .accentColor : .secondary)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Ollama").font(.caption.bold())
                Text(bridge.ollamaUp ? "Corriendo · \(bridge.ollamaModels) modelo(s)" : "Servidor parado")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: openMainWindow) {
                Label("Abrir MT3K Mac Tools", systemImage: "app.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button {
                NSApp.hide(nil)
            } label: {
                Label("Ocultar ventana", systemImage: "eye.slash.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Toggle(isOn: loginBinding) {
                Label("Abrir al iniciar macOS", systemImage: "poweron")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .help(loginItem.statusText)

            if loginItem.status == .requiresApproval {
                Button {
                    loginItem.openLoginItemsSettings()
                } label: {
                    Label("Aprobar en Login Items", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }

            Button {
                Task { await bridge.refresh() }
            } label: {
                Label("Refrescar estado", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Salir", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { enabled in
                Task { await loginItem.setEnabled(enabled) }
            }
        )
    }

    private var footer: some View {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let stamp = bridge.lastUpdate == .distantPast ? "nunca" : formatter.localizedString(for: bridge.lastUpdate, relativeTo: Date())
        return VStack(alignment: .leading, spacing: 2) {
            if !bridge.uptime.isEmpty || bridge.processCount > 0 {
                HStack {
                    if !bridge.uptime.isEmpty {
                        Text("Uptime: \(bridge.uptime)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if bridge.processCount > 0 {
                        Text("\(bridge.processCount) procesos")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            HStack {
                Text("Última actualización: \(stamp)")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
            }
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        // Find existing main window or trigger one by opening a default scene.
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("MT3K") == true || $0.title.contains("MT3K") }) ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSApplication.unhideAllApplications(_:)), to: nil, from: nil)
        }
    }
}

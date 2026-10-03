import Foundation
import SwiftUI
import AppKit

// MARK: - Models

struct ProcessSample: Identifiable, Hashable {
    let id: String
    let pid: String
    let name: String
    let value: String           // "12.3%" o "1.8 GB"
    let rawValue: Double
}

struct LiveStats {
    var cpuTotal: Double = 0
    var cpuUser: Double = 0
    var cpuSys: Double = 0
    var cpuIdle: Double = 100

    var gpuUsagePercent: Double = .nan
    var gpuRendererPercent: Double = .nan
    var gpuTilerPercent: Double = .nan
    var gpuMemoryGB: Double = 0

    var ramUsedGB: Double = 0
    var ramTotalGB: Double = 0
    var memPressureLabel: String = "—"
    var memPressureColor: String = "gray"

    var swapUsedGB: Double = 0
    var swapTotalGB: Double = 0

    var diskFreeGB: Double = 0
    var diskTotalGB: Double = 0
    var diskUsedPercent: Double = 0

    var batteryPercent: Int = -1
    var batteryCharging: Bool = false
    var batteryCycles: Int = 0
    var batteryCondition: String = ""

    var loadAvg1: Double = 0
    var loadAvg5: Double = 0
    var loadAvg15: Double = 0

    var thermalState: Int = 0       // 0=nominal, 4=critical
    var thermalLabel: String = "Nominal"

    var temperatureC: String = "—"
    var temperatureSource: String = ""
    var hasTemperature: Bool = false

    var processCount: Int = 0
    var uptime: String = ""

    var topCPU: [ProcessSample] = []
    var topRAM: [ProcessSample] = []
}

// MARK: - State

@MainActor
final class StatsState: ObservableObject {
    @Published var stats: LiveStats = LiveStats()
    @Published var autoRefresh: Bool = true
    @Published var refreshInterval: Double = 3.0
    @Published var lastUpdate: Date = .distantPast

    private var refreshInFlight = false
    private var pollTimer: Timer?

    func start() {
        stopTimer()
        Task { await refresh() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoRefresh else { return }
                await self.refresh()
            }
        }
    }

    func stop() {
        stopTimer()
    }

    private func stopTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func toggleAutoRefresh() {
        autoRefresh.toggle()
        if autoRefresh { start() }
    }

    func refresh() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        var s = self.stats   // mantén el estado previo si algún capture falla

        // Capturas secuenciales (rápidas — todas <50ms en zsh -lc). Si una falla,
        // las siguientes siguen ejecutándose porque cada función ya devuelve
        // valores por defecto en caso de error.
        let cpu = await captureCPU()
        s.cpuUser = cpu.user
        s.cpuSys = cpu.sys
        s.cpuIdle = cpu.idle
        s.cpuTotal = min(100, cpu.user + cpu.sys)

        if let gpu = await GPUUsageReader.read() {
            s.gpuUsagePercent = gpu.devicePercent
            s.gpuRendererPercent = gpu.rendererPercent
            s.gpuTilerPercent = gpu.tilerPercent
            s.gpuMemoryGB = gpu.memoryGB
        } else {
            s.gpuUsagePercent = .nan
            s.gpuRendererPercent = .nan
            s.gpuTilerPercent = .nan
            s.gpuMemoryGB = 0
        }

        let ram = await captureRAM()
        s.ramUsedGB = ram.used
        s.ramTotalGB = ram.total
        s.memPressureLabel = ram.pressureLabel
        s.memPressureColor = ram.pressureColor

        let swap = await captureSwap()
        s.swapUsedGB = swap.used
        s.swapTotalGB = swap.total

        let disk = await captureDisk()
        s.diskFreeGB = disk.free
        s.diskTotalGB = disk.total
        s.diskUsedPercent = disk.usedPercent

        let bat = await captureBattery()
        s.batteryPercent = bat.percent
        s.batteryCharging = bat.charging
        s.batteryCycles = bat.cycles
        s.batteryCondition = bat.condition

        let load = await captureLoad()
        s.loadAvg1 = load.l1
        s.loadAvg5 = load.l5
        s.loadAvg15 = load.l15

        let therm = await captureThermal()
        s.thermalState = therm.state
        s.thermalLabel = therm.label

        let temperature = await captureTemperature()
        s.hasTemperature = !temperature.value.isEmpty
        s.temperatureC = temperature.value.isEmpty ? "—" : temperature.value
        s.temperatureSource = temperature.source

        let processes = StatsParsers.processTable(
            fromPS: await run("/bin/ps", ["-A", "-o", "pid=,%cpu=,rss=,comm="]), limit: 5)
        s.processCount = processes.count
        s.uptime = await captureUptime()
        s.topCPU = processes.topCPU
        s.topRAM = processes.topRAM

        self.stats = s
        self.lastUpdate = Date()
    }

    // MARK: - Captura individual

    private struct CPUVals { var user: Double; var sys: Double; var idle: Double }
    private func captureCPU() async -> CPUVals {
        // top -l 1 -n 0 sin pipes (el grep|head fallaba dentro del Process).
        // Parseamos la línea "CPU usage: X% user, Y% sys, Z% idle" en Swift.
        let out = await run("/usr/bin/top", ["-l", "1", "-n", "0"])
        guard let cpu = StatsParsers.cpuUsage(fromTop: out) else {
            return CPUVals(user: 0, sys: 0, idle: 100)
        }
        return CPUVals(user: cpu.user, sys: cpu.sys, idle: cpu.idle)
    }

    private struct RAMVals { var used: Double; var total: Double; var pressureLabel: String; var pressureColor: String }
    private func captureRAM() async -> RAMVals {
        async let vmStat = run("/usr/bin/vm_stat", [])
        let total = SystemInfo.physicalMemoryGB
        let used = StatsParsers.memory(fromVMStat: await vmStat).usedGB

        let pressure = SystemInfo.memoryPressure
        return RAMVals(used: used, total: total, pressureLabel: pressure.label, pressureColor: pressure.color)
    }

    private struct SwapVals { var used: Double; var total: Double }
    private func captureSwap() async -> SwapVals {
        guard let swap = SystemInfo.swapUsage else { return SwapVals(used: 0, total: 0) }
        return SwapVals(used: swap.usedGB, total: swap.totalGB)
    }

    private struct DiskVals { var free: Double; var total: Double; var usedPercent: Double }
    private func captureDisk() async -> DiskVals {
        // On modern APFS macOS, "/" is the sealed system snapshot and reports
        // only the OS volume usage. User data lives on /System/Volumes/Data.
        let dataPath = FileManager.default.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : "/"
        let out = await run("/bin/df", ["-k", dataPath])
        guard let disk = StatsParsers.disk(fromDF: out) else {
            return DiskVals(free: 0, total: 0, usedPercent: 0)
        }
        return DiskVals(free: disk.freeGB, total: disk.totalGB, usedPercent: disk.usedPercent)
    }

    private struct BatteryVals { var percent: Int; var charging: Bool; var cycles: Int; var condition: String }
    private func captureBattery() async -> BatteryVals {
        let out = await run("/usr/bin/pmset", ["-g", "batt"])
        var percent = -1
        var charging = false
        if let m = out.range(of: #"(\d+)%"#, options: .regularExpression) {
            percent = Int(out[m].dropLast()) ?? -1
        }
        if out.contains("charging") || out.contains("charged") || out.contains("AC attached") {
            charging = true
        }
        if out.contains("discharging") {
            charging = false
        }
        // Cycles + condition cambian lentamente; los capturamos cada vez (es barato vía SPPowerDataType pero
        // toma ~1s. Vamos al ioreg que es instantáneo):
        let info = await run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"])
        let cycles = StatsParsers.cycleCount(fromIoreg: info)
        return BatteryVals(percent: percent, charging: charging, cycles: cycles, condition: "")
    }

    private struct LoadVals { var l1: Double; var l5: Double; var l15: Double }
    private func captureLoad() async -> LoadVals {
        guard let load = SystemInfo.loadAverages else { return LoadVals(l1: 0, l5: 0, l15: 0) }
        return LoadVals(l1: load.l1, l5: load.l5, l15: load.l15)
    }

    private struct ThermalVals { var state: Int; var label: String }
    private func captureThermal() async -> ThermalVals {
        let thermal = SystemInfo.thermalLevel
        return ThermalVals(state: thermal.state, label: thermal.label)
    }

    /// Lee temperatura. Prefiere IOHID nativo (Apple Silicon, sin sudo).
    /// Fallback a osx-cpu-temp (sólo Intel, M-series devuelve 0.0°C).
    private struct TemperatureVals { var value: String; var source: String }
    private func captureTemperature() async -> TemperatureVals {
        // 1) Path nativo Apple Silicon vía IOHID dlsym
        if let reading = MacTemperature.shared.read(),
           let temp = reading.displayTemperatureC {
            return TemperatureVals(value: String(format: "%.0f°C", temp), source: "iohid")
        }
        // 2) Fallback a osx-cpu-temp (Intel)
        guard let tempTool = findExecutable("osx-cpu-temp") else {
            return TemperatureVals(value: "", source: "")
        }
        let out = await run(tempTool, [])
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return TemperatureVals(value: "", source: "osx-cpu-temp") }
        let numericPart = trimmed.replacingOccurrences(of: "°C", with: "")
            .replacingOccurrences(of: "°F", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let value = Double(numericPart), value < 1.0 {
            return TemperatureVals(value: "", source: "apple-silicon-unsupported")
        }
        return TemperatureVals(value: trimmed, source: "osx-cpu-temp")
    }

    /// Lectura completa (no string, valores numéricos) — usada por el menu bar.
    func detailedTemperature() -> TemperatureReading? {
        MacTemperature.shared.read()
    }

    private func captureUptime() async -> String {
        guard let boot = SystemInfo.bootTime else { return "" }
        return StatsParsers.formatUptime(Date().timeIntervalSince(boot))
    }

    private func parseMemSize(_ raw: String) -> Double {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = s.last else { return 0 }
        let numText = s.dropLast()
        guard let num = Double(numText) else { return Double(s) ?? 0 }
        switch last {
        case "K", "k": return num * 1024
        case "M", "m": return num * 1024 * 1024
        case "G", "g": return num * 1024 * 1024 * 1024
        case "T", "t": return num * 1024 * 1024 * 1024 * 1024
        default: return Double(s) ?? 0
        }
    }

    private func findExecutable(_ name: String) -> String? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = (pathEntries + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .map { "\($0)/\(name)" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ executable: String, _ args: [String]) async -> String {
        (try? await runShell(executable: executable, args: args)) ?? ""
    }
}

// MARK: - View

struct StatsSection: View {
    @StateObject private var state = StatsState()
    @State private var hasOSXCPUTemp: Bool = false

    var body: some View {
        SystemPanel(title: "Live Stats", symbol: "gauge.with.dots.needle.bottom.50percent") {
            controlBar
            kpiGrid
            if !state.stats.topCPU.isEmpty || !state.stats.topRAM.isEmpty {
                processTables
            }
            if !state.stats.hasTemperature {
                tempHint
            }
        }
        .onAppear { state.start() }
        .onDisappear { state.stop() }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Image(systemName: state.autoRefresh ? "play.circle.fill" : "pause.circle.fill")
                .foregroundColor(state.autoRefresh ? Theme.green : Theme.amber)
            Button(state.autoRefresh ? "Auto-refresh: ON" : "Auto-refresh: OFF") {
                state.toggleAutoRefresh()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Text("· cada \(Int(state.refreshInterval))s")
                .font(.caption2).foregroundColor(Theme.textSecondary)
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            let stamp = state.lastUpdate == .distantPast ? "—" : relativeStamp(state.lastUpdate)
            Text("Actualizado: \(stamp)")
                .font(.caption2).foregroundColor(Theme.textSecondary)
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            cpuTile
            gpuTile
            ramTile
            swapTile
            diskTile
            batteryTile
            loadTile
            thermalTile
            tempTile
            processCountTile
            uptimeTile
        }
    }

    private var cpuTile: some View {
        StatsTile(title: "CPU", value: String(format: "%.0f%%", state.stats.cpuTotal),
                  detail: "user \(fmt(state.stats.cpuUser)) · sys \(fmt(state.stats.cpuSys))",
                  symbol: "cpu.fill",
                  fill: state.stats.cpuTotal / 100.0,
                  color: cpuColor)
    }

    private var cpuColor: Color {
        switch state.stats.cpuTotal {
        case 80...: return Theme.sevCritical
        case 50..<80: return Theme.amber
        default: return Theme.green
        }
    }

    private var gpuTile: some View {
        let hasGPU = !state.stats.gpuUsagePercent.isNaN
        let detail = hasGPU
            ? String(format: "Renderer %.0f%% · Tiler %.0f%%\n%.1f GB", state.stats.gpuRendererPercent, state.stats.gpuTilerPercent, state.stats.gpuMemoryGB)
            : "AGX no disponible"
        return StatsTile(title: "GPU", value: hasGPU ? String(format: "%.0f%%", state.stats.gpuUsagePercent) : "—",
                         detail: detail,
                         symbol: "display",
                         fill: hasGPU ? state.stats.gpuUsagePercent / 100.0 : 0,
                         color: gpuColor)
    }

    private var gpuColor: Color {
        if state.stats.gpuUsagePercent.isNaN { return Theme.textSecondary }
        switch state.stats.gpuUsagePercent {
        case 80...: return Theme.sevCritical
        case 50..<80: return Theme.amber
        default: return Theme.green
        }
    }

    private var ramTile: some View {
        let used = state.stats.ramUsedGB, total = max(state.stats.ramTotalGB, 1)
        return StatsTile(title: "RAM", value: String(format: "%.1f/%.0f GB", used, total),
                         detail: "Pressure: \(state.stats.memPressureLabel)",
                         symbol: "memorychip.fill",
                         fill: used / total,
                         color: pressureColor)
    }

    private var pressureColor: Color {
        switch state.stats.memPressureColor {
        case "red": return Theme.sevCritical
        case "orange": return Theme.amber
        default: return Theme.green
        }
    }

    private var swapTile: some View {
        let used = state.stats.swapUsedGB, total = max(state.stats.swapTotalGB, 0.01)
        return StatsTile(title: "Swap", value: String(format: "%.2f/%.1f GB", used, total),
                         detail: total < 0.05 ? "Sin swap activo" : "\(Int((used/total)*100))% usado",
                         symbol: "externaldrive.connected.to.line.below",
                         fill: total > 0 ? used / total : 0,
                         color: used > 0.5 ? Theme.amber : Theme.green)
    }

    private var diskTile: some View {
        StatsTile(title: "Disco /", value: String(format: "%.0f GB", state.stats.diskFreeGB),
                  detail: String(format: "%.0f%% usado · %.0f GB total", state.stats.diskUsedPercent, state.stats.diskTotalGB),
                  symbol: "internaldrive.fill",
                  fill: state.stats.diskUsedPercent / 100.0,
                  color: state.stats.diskUsedPercent > 85 ? Theme.sevCritical : Theme.green)
    }

    @ViewBuilder
    private var batteryTile: some View {
        if state.stats.batteryPercent >= 0 {
            StatsTile(
                title: "Batería",
                value: "\(state.stats.batteryPercent)%",
                detail: "\(state.stats.batteryCharging ? "Cargando" : "Descargando") · \(state.stats.batteryCycles) ciclos",
                symbol: state.stats.batteryCharging ? "battery.100.bolt" : "battery.50",
                fill: Double(state.stats.batteryPercent) / 100.0,
                color: state.stats.batteryPercent < 20 ? Theme.sevCritical : Theme.green
            )
        } else {
            StatsTile(title: "Batería", value: "—", detail: "Sin batería (desktop)",
                      symbol: "powerplug.fill", fill: 0, color: Theme.textSecondary)
        }
    }

    private var loadTile: some View {
        StatsTile(title: "Load avg", value: String(format: "%.2f", state.stats.loadAvg1),
                  detail: String(format: "5m %.2f · 15m %.2f", state.stats.loadAvg5, state.stats.loadAvg15),
                  symbol: "waveform.path.ecg",
                  fill: min(state.stats.loadAvg1 / 8.0, 1.0),
                  color: state.stats.loadAvg1 > 6 ? Theme.amber : Theme.blue)
    }

    private var thermalTile: some View {
        StatsTile(title: "Thermal", value: state.stats.thermalLabel,
                  detail: "Nivel \(state.stats.thermalState)/3",
                  symbol: "thermometer.medium",
                  fill: Double(state.stats.thermalState) / 3.0,
                  color: state.stats.thermalState >= 2 ? Theme.amber : Theme.green)
    }

    private var tempTile: some View {
        let detail: String
        if state.stats.temperatureSource == "iohid" {
            detail = "sensor nativo IOHID"
        } else if state.stats.temperatureSource == "osx-cpu-temp" {
            detail = "via osx-cpu-temp"
        } else {
            detail = "sensor no disponible"
        }
        return StatsTile(title: "Temp CPU", value: state.stats.temperatureC,
                         detail: detail,
                         symbol: "thermometer.high",
                         fill: tempFraction,
                         color: tempColor)
    }

    private var tempFraction: Double {
        // Parseo "62.0°C" si está disponible
        let raw = state.stats.temperatureC.replacingOccurrences(of: "°C", with: "").trimmingCharacters(in: .whitespaces)
        if let v = Double(raw) {
            return min(v / 100.0, 1.0)
        }
        return 0
    }

    private var tempColor: Color {
        let raw = state.stats.temperatureC.replacingOccurrences(of: "°C", with: "").trimmingCharacters(in: .whitespaces)
        if let v = Double(raw) {
            if v > 85 { return Theme.sevCritical }
            if v > 70 { return Theme.amber }
            return Theme.green
        }
        return Theme.textSecondary
    }

    private var processCountTile: some View {
        StatsTile(title: "Procesos", value: "\(state.stats.processCount)",
                  detail: "totales", symbol: "list.bullet.rectangle.fill",
                  fill: 0, color: Theme.blue)
    }

    private var uptimeTile: some View {
        StatsTile(title: "Uptime", value: state.stats.uptime.isEmpty ? "—" : state.stats.uptime,
                  detail: "desde último boot", symbol: "clock.fill",
                  fill: 0, color: Theme.textSecondary)
    }

    private var processTables: some View {
        HStack(alignment: .top, spacing: 12) {
            processTable(title: "Top CPU", samples: state.stats.topCPU, color: Theme.accent)
            processTable(title: "Top RAM", samples: state.stats.topRAM, color: Theme.blue)
        }
    }

    private func processTable(title: String, samples: [ProcessSample], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").foregroundColor(color)
                Text(title).font(.caption.bold())
                Spacer()
            }
            ForEach(samples) { p in
                HStack {
                    Text(p.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(p.value).font(.system(.caption, design: .monospaced)).bold().foregroundColor(color)
                    Text("pid \(p.pid)").font(.caption2).foregroundColor(Theme.textSecondary).frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 2)
            }
            if samples.isEmpty {
                Text("Sampling...").font(.caption).foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.bgDark)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var tempHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundColor(Theme.blue).font(.caption)
            Text(tempHintMessage)
                .font(.caption2).foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Theme.blue.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.blue.opacity(0.25)))
        .clipShape(.rect(cornerRadius: 6))
    }

    private var tempHintMessage: String {
        if state.stats.temperatureSource == "apple-silicon-unsupported" {
            return "osx-cpu-temp solo lee sensores SMC Intel. Para Apple Silicon usa **asitop** o **mactop con sudo** (Apps → Utilidades) — leen GPU/ANE/temp vía IOReport sin necesidad de polling cada 3s."
        }
        return "Esperando sensor nativo IOHID. Si no aparece, instala `osx-cpu-temp` en Intel o usa **asitop/mactop con sudo** desde Apps → Utilidades para ver GPU/ANE."
    }

    private func fmt(_ v: Double) -> String { String(format: "%.0f%%", v) }

    private func relativeStamp(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Tile

private struct StatsTile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let fill: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundColor(color)
                    .frame(width: 18, alignment: .leading)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(height: 24, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(fill > 0 ? 0.15 : 0.08)).frame(height: 4)
                    Capsule().fill(color).frame(width: geo.size.width * min(max(fill, 0), 1), height: 4)
                }
            }
            .frame(height: 4)
            Text(detail)
                .font(.caption2)
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(height: 30, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 8))
    }
}

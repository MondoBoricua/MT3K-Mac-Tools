// Menu bar — MenuBarBridge: polling y captura de métricas para popovers y medidores.
import SwiftUI
import AppKit

@MainActor
final class MenuBarBridge: ObservableObject {
    @Published var ollamaUp: Bool = false
    @Published var ollamaModels: Int = 0
    @Published var caffeinatePID: Int32?
    @Published var caffeinateMode: String = ""
    @Published var ramUsedGB: Double = 0
    @Published var ramTotalGB: Double = 0
    @Published var ramAppGB: Double = 0
    @Published var ramWiredGB: Double = 0
    @Published var ramCompressedGB: Double = 0
    @Published var ramFreeGB: Double = 0
    @Published var swapUsedGB: Double = 0
    @Published var swapTotalGB: Double = 0
    @Published var diskFreeGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var diskUsedPercent: Double = 0
    @Published var cpuTotal: Double = 0
    @Published var cpuUser: Double = 0
    @Published var cpuSys: Double = 0
    @Published var cpuIdle: Double = 100
    @Published var loadAvg1: Double = 0
    @Published var loadAvg5: Double = 0
    @Published var loadAvg15: Double = 0
    @Published var uptime: String = ""
    @Published var processCount: Int = 0
    @Published var batteryCycles: Int = 0
    @Published var brewOutdatedCount: Int = 0
    @Published var gpuUsagePercent: Double = .nan
    @Published var gpuRendererPercent: Double = .nan
    @Published var gpuTilerPercent: Double = .nan
    @Published var gpuMemoryGB: Double = 0
    @Published var topCPU: [ProcessSample] = []
    @Published var topRAM: [ProcessSample] = []
    @Published var cpuHistory: [Double] = []
    @Published var ramHistory: [Double] = []
    @Published var diskHistory: [Double] = []
    @Published var lastUpdate: Date = .distantPast

    // Temperatura nativa (IOHID en Apple Silicon)
    @Published var cpuTempC: Double = .nan
    @Published var gpuTempC: Double = .nan
    @Published var cpuTempMax: Double = .nan

    private var pollTimer: Timer?
    private var pollInterval: TimeInterval = 60
    private var pollMode: PollMode = .full
    private let maxHistorySamples = 48
    private var brewCheckTask: Task<Void, Never>?

    func startPolling(interval: TimeInterval = 60) {
        startPolling(interval: interval, mode: .full)
    }

    func startCompactPolling(interval: TimeInterval = 15) {
        startPolling(interval: interval, mode: .compact)
    }

    func refreshCaffeineStatus() {
        caffeinatePID = MT3KCaffeinate.activePID()
        caffeinateMode = MT3KCaffeinate.mode
    }

    private func startPolling(interval: TimeInterval, mode: PollMode) {
        if pollTimer != nil, pollInterval <= interval { return }
        pollInterval = interval
        pollMode = mode
        Task { await refresh(mode: mode) }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(mode: mode)
            }
        }
    }

    func refresh(mode: PollMode = .full) async {
        if mode == .compact {
            await refreshCompactMetrics()
            return
        }

        // Ollama — un solo GET a /api/tags resuelve "¿está arriba?" y el conteo de modelos
        let ollama = await fetchOllamaStatus()
        ollamaUp = ollama.up
        ollamaModels = ollama.models

        // Temperatura nativa Apple Silicon (IOHID)
        if let reading = MacTemperature.shared.read() {
            cpuTempC = reading.cpuPerformanceC
            gpuTempC = reading.gpuC
            cpuTempMax = reading.cpuMaxC
        } else {
            cpuTempC = .nan
            gpuTempC = .nan
            cpuTempMax = .nan
        }

        caffeinatePID = MT3KCaffeinate.activePID()
        caffeinateMode = MT3KCaffeinate.mode

        let ram = await captureRAM()
        ramUsedGB = ram.used
        ramTotalGB = ram.total
        ramAppGB = ram.app
        ramWiredGB = ram.wired
        ramCompressedGB = ram.compressed
        ramFreeGB = ram.free
        let swap = await captureSwap()
        swapUsedGB = swap.used
        swapTotalGB = swap.total
        let disk = await captureDisk()
        diskFreeGB = disk.free
        diskTotalGB = disk.total
        diskUsedPercent = disk.usedPercent
        let cpu = await captureCPU()
        cpuUser = cpu.user
        cpuSys = cpu.sys
        cpuIdle = cpu.idle
        cpuTotal = min(100, cpu.user + cpu.sys)
        let load = await captureLoad()
        loadAvg1 = load.l1
        loadAvg5 = load.l5
        loadAvg15 = load.l15
        uptime = await captureUptime()
        processCount = await captureProcessCount()
        batteryCycles = StatsParsers.cycleCount(fromIoreg: await run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"]))
        scheduleBrewOutdatedCheck()
        topCPU = await captureTopProcesses(by: .cpu)
        topRAM = await captureTopProcesses(by: .memory)
        if let gpu = await GPUUsageReader.read() {
            gpuUsagePercent = gpu.devicePercent
            gpuRendererPercent = gpu.rendererPercent
            gpuTilerPercent = gpu.tilerPercent
            gpuMemoryGB = gpu.memoryGB
        } else {
            gpuUsagePercent = .nan
            gpuRendererPercent = .nan
            gpuTilerPercent = .nan
            gpuMemoryGB = 0
        }

        appendHistory(cpuTotal, to: &cpuHistory)
        appendHistory(ramTotalGB > 0 ? (ramUsedGB / ramTotalGB) * 100 : .nan, to: &ramHistory)
        appendHistory(diskUsedPercent, to: &diskHistory)
        lastUpdate = Date()
    }

    private func refreshCompactMetrics() async {
        let active = activeCompactMetrics
        refreshCaffeineStatus()

        if active.isEmpty {
            if pollMode == .compact {
                pollTimer?.invalidate()
                pollTimer = nil
                pollInterval = 60
            }
            return
        }

        if active.contains(.cpu) {
            if let reading = MacTemperature.shared.read() {
                cpuTempC = reading.cpuPerformanceC
                gpuTempC = reading.gpuC
                cpuTempMax = reading.cpuMaxC
            } else {
                cpuTempC = .nan
                gpuTempC = .nan
                cpuTempMax = .nan
            }
            let cpu = await captureCPU()
            cpuUser = cpu.user
            cpuSys = cpu.sys
            cpuIdle = cpu.idle
            cpuTotal = min(100, cpu.user + cpu.sys)
            appendHistory(cpuTotal, to: &cpuHistory)
        }

        if active.contains(.ram) {
            let ram = await captureRAM()
            ramUsedGB = ram.used
            ramTotalGB = ram.total
            ramAppGB = ram.app
            ramWiredGB = ram.wired
            ramCompressedGB = ram.compressed
            ramFreeGB = ram.free
            appendHistory(ramTotalGB > 0 ? (ramUsedGB / ramTotalGB) * 100 : .nan, to: &ramHistory)
        }

        if active.contains(.disk) {
            let disk = await captureDisk()
            diskFreeGB = disk.free
            diskTotalGB = disk.total
            diskUsedPercent = disk.usedPercent
            appendHistory(diskUsedPercent, to: &diskHistory)
        }

        if active.contains(.gpu) {
            if let gpu = await GPUUsageReader.read() {
                gpuUsagePercent = gpu.devicePercent
                gpuRendererPercent = gpu.rendererPercent
                gpuTilerPercent = gpu.tilerPercent
                gpuMemoryGB = gpu.memoryGB
            } else {
                gpuUsagePercent = .nan
                gpuRendererPercent = .nan
                gpuTilerPercent = .nan
                gpuMemoryGB = 0
            }
        }

        lastUpdate = Date()
    }

    func toggleCaffeine() async {
        if MT3KCaffeinate.activePID() != nil {
            _ = MT3KCaffeinate.stop()
        } else {
            _ = try? MT3KCaffeinate.start(
                args: ["-d", "-i", "-m", "-s", "-u"],
                mode: "Caffeine agresivo · pantalla despierta"
            )
        }
        await refresh()
    }

    private func fetchOllamaStatus() async -> (up: Bool, models: Int) {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return (false, 0) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (false, 0) }
            struct R: Decodable { struct M: Decodable {}; let models: [M] }
            let count = (try? JSONDecoder().decode(R.self, from: data).models.count) ?? 0
            return (true, count)
        } catch {
            return (false, 0)
        }
    }

    private struct RAMSnapshot {
        let used: Double
        let total: Double
        let app: Double
        let wired: Double
        let compressed: Double
        let free: Double
    }
    private struct CPUSnapshot { let user: Double; let sys: Double; let idle: Double }
    private struct SwapSnapshot { let used: Double; let total: Double }
    private struct LoadSnapshot { let l1: Double; let l5: Double; let l15: Double }
    private enum ProcessSortKey { case cpu, memory }
    enum PollMode { case compact, full }

    private var activeCompactMetrics: Set<CompactMenuMetric> {
        var active = Set<CompactMenuMetric>()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "menuMetricDiskEnabled") { active.insert(.disk) }
        if defaults.bool(forKey: "menuMetricCPUEnabled") { active.insert(.cpu) }
        if defaults.bool(forKey: "menuMetricGPUEnabled") { active.insert(.gpu) }
        if defaults.bool(forKey: "menuMetricRAMEnabled") { active.insert(.ram) }
        return active
    }

    private func captureCPU() async -> CPUSnapshot {
        let out = await run("/usr/bin/top", ["-l", "1", "-n", "0"])
        if let cpu = StatsParsers.cpuUsage(fromTop: out) {
            return CPUSnapshot(user: cpu.user, sys: cpu.sys, idle: cpu.idle)
        }
        return CPUSnapshot(user: 0, sys: 0, idle: 100)
    }

    private func captureRAM() async -> RAMSnapshot {
        async let totalRaw = run("/usr/sbin/sysctl", ["-n", "hw.memsize"])
        async let vmStat = run("/usr/bin/vm_stat", [])
        let total = (Double((await totalRaw).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) / 1_073_741_824.0
        let memory = StatsParsers.memory(fromVMStat: await vmStat)
        return RAMSnapshot(
            used: memory.usedGB,
            total: total,
            app: memory.appGB,
            wired: memory.wiredGB,
            compressed: memory.compressedGB,
            free: max(0, total - memory.usedGB)
        )
    }

    private func captureSwap() async -> SwapSnapshot {
        let out = await run("/usr/sbin/sysctl", ["vm.swapusage"])
        guard let swap = StatsParsers.swapGB(fromSysctl: out) else { return SwapSnapshot(used: 0, total: 0) }
        return SwapSnapshot(used: swap.used, total: swap.total)
    }

    private struct DiskSnapshot { let free: Double; let total: Double; let usedPercent: Double }
    private func captureDisk() async -> DiskSnapshot {
        let dataPath = FileManager.default.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : "/"
        let out = await run("/bin/df", ["-k", dataPath])
        guard let disk = StatsParsers.disk(fromDF: out) else { return DiskSnapshot(free: 0, total: 0, usedPercent: 0) }
        return DiskSnapshot(free: disk.freeGB, total: disk.totalGB, usedPercent: disk.usedPercent)
    }

    private func captureLoad() async -> LoadSnapshot {
        let out = await run("/usr/sbin/sysctl", ["-n", "vm.loadavg"])
        guard let load = StatsParsers.loadAverages(fromSysctl: out) else { return LoadSnapshot(l1: 0, l5: 0, l15: 0) }
        return LoadSnapshot(l1: load.l1, l5: load.l5, l15: load.l15)
    }

    private func captureProcessCount() async -> Int {
        let out = await run("/bin/ps", ["-A", "-o", "pid="])
        return max(0, out.split(whereSeparator: \.isNewline).count)
    }

    // brew outdated tarda segundos — corre aparte del refresh para que el
    // popover abra al instante y el badge aparezca cuando termine.
    private func scheduleBrewOutdatedCheck() {
        guard brewCheckTask == nil else { return }
        brewCheckTask = Task { [weak self] in
            guard let self else { return }
            defer { self.brewCheckTask = nil }
            let brew = "/opt/homebrew/bin/brew"
            guard FileManager.default.isExecutableFile(atPath: brew) else { return }
            let formulae = await self.run(brew, ["outdated", "--quiet"])
            let casks = await self.run(brew, ["outdated", "--cask", "--quiet"])
            guard !Task.isCancelled else { return }
            self.brewOutdatedCount = formulae.split(whereSeparator: \.isNewline).count
                + casks.split(whereSeparator: \.isNewline).count
        }
    }

    private func captureUptime() async -> String {
        let raw = await run("/usr/sbin/sysctl", ["-n", "kern.boottime"])
        guard let match = raw.range(of: #"sec\s*=\s*([0-9]+)"#, options: .regularExpression) else { return "" }
        let digits = raw[match].filter(\.isNumber)
        guard let seconds = TimeInterval(digits) else { return "" }
        return formatUptime(Date().timeIntervalSince(Date(timeIntervalSince1970: seconds)))
    }

    private func captureTopProcesses(by key: ProcessSortKey) async -> [ProcessSample] {
        let sortFlag = key == .cpu ? "-r" : "-m"
        let out = await run("/bin/ps", ["-A", sortFlag, "-o", "pid=,%cpu=,rss=,comm="])
        var result: [ProcessSample] = []
        for line in out.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4,
                  let _ = Int(parts[0]),
                  let cpuPct = Double(parts[1]),
                  let rssKB = Int(parts[2]) else { continue }
            let pid = parts[0]
            let name = (parts[3] as NSString).lastPathComponent
            let raw: Double
            let value: String
            if key == .cpu {
                raw = cpuPct
                value = String(format: "%.1f%%", cpuPct)
            } else {
                raw = Double(rssKB) * 1024
                value = formatBytes(raw)
            }
            result.append(ProcessSample(id: "\(pid)-\(name)", pid: pid, name: name, value: value, rawValue: raw))
            if result.count >= 7 { break }
        }
        return result
    }

    private func appendHistory(_ value: Double, to history: inout [Double]) {
        guard !value.isNaN else { return }
        history.append(max(0, min(100, value)))
        if history.count > maxHistorySamples {
            history.removeFirst(history.count - maxHistorySamples)
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func formatBytes(_ bytes: Double) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    private func checked(_ command: String) async -> String {
        (try? await runShell(executable: "/bin/zsh", args: ["-lc", "\(command) || true"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func run(_ executable: String, _ args: [String]) async -> String {
        (try? await runShell(executable: executable, args: args))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // No deinit cleanup of `pollTimer`: `@MainActor` classes can't access non-Sendable
    // refs from nonisolated `deinit` in Swift 6. The process tearing down releases the timer.
}

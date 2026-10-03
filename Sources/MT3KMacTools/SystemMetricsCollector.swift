import Foundation
import Darwin

/// Una captura por métrica, compartida entre el menú y el panel Stats.
@MainActor
final class SystemMetricsCollector {
    static let shared = SystemMetricsCollector()

    struct CPUSnapshot: Sendable { let user: Double; let sys: Double; let idle: Double }
    struct RAMSnapshot: Sendable {
        let used: Double
        let total: Double
        let app: Double
        let wired: Double
        let compressed: Double
        let free: Double
    }
    struct SwapSnapshot: Sendable { let used: Double; let total: Double }
    struct DiskSnapshot: Sendable { let free: Double; let total: Double; let usedPercent: Double }
    struct LoadSnapshot: Sendable { let l1: Double; let l5: Double; let l15: Double }

    @MainActor
    final class MetricCache<Value: Sendable> {
        private var cached: (value: Value, capturedAt: ContinuousClock.Instant)?
        private var inFlight: Task<Value, Never>?

        func value(maxAge: TimeInterval, capture: @escaping @MainActor () async -> Value) async -> Value {
            if let cached, cached.capturedAt.duration(to: .now) < .seconds(maxAge) {
                return cached.value
            }
            if let inFlight { return await inFlight.value }
            let task = Task {
                let value = await capture()
                cached = (value, .now)
                inFlight = nil
                return value
            }
            inFlight = task
            return await task.value
        }
    }

    private let cpuCache = MetricCache<CPUSnapshot>()
    private let ramCache = MetricCache<RAMSnapshot>()
    private let diskCache = MetricCache<DiskSnapshot>()
    private let gpuCache = MetricCache<GPUUsageReading?>()
    private let swapCache = MetricCache<SwapSnapshot>()
    private let loadCache = MetricCache<LoadSnapshot>()
    private let processCache = MetricCache<StatsParsers.ProcessTable>()
    private let cyclesCache = MetricCache<Int>()
    private var previousTicks: StatsParsers.CPUTicks?
    private var lastCPU = CPUSnapshot(user: 0, sys: 0, idle: 100)

    func cpu(maxAge: TimeInterval) async -> CPUSnapshot {
        await cpuCache.value(maxAge: maxAge) { await self.captureCPU() }
    }

    func ram(maxAge: TimeInterval) async -> RAMSnapshot {
        await ramCache.value(maxAge: maxAge) {
            let total = SystemInfo.physicalMemoryGB
            let memory = StatsParsers.memory(fromVMStat: await self.run("/usr/bin/vm_stat", []))
            return RAMSnapshot(used: memory.usedGB, total: total, app: memory.appGB,
                               wired: memory.wiredGB, compressed: memory.compressedGB,
                               free: max(0, total - memory.usedGB))
        }
    }

    func disk(maxAge: TimeInterval) async -> DiskSnapshot {
        await diskCache.value(maxAge: maxAge) {
            let path = FileManager.default.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : "/"
            let out = await self.run("/bin/df", ["-k", path])
            guard let disk = StatsParsers.disk(fromDF: out) else {
                return DiskSnapshot(free: 0, total: 0, usedPercent: 0)
            }
            return DiskSnapshot(free: disk.freeGB, total: disk.totalGB, usedPercent: disk.usedPercent)
        }
    }

    func gpu(maxAge: TimeInterval) async -> GPUUsageReading? {
        await gpuCache.value(maxAge: maxAge) { await GPUUsageReader.read() }
    }

    func swap(maxAge: TimeInterval) async -> SwapSnapshot {
        await swapCache.value(maxAge: maxAge) {
            guard let swap = SystemInfo.swapUsage else { return SwapSnapshot(used: 0, total: 0) }
            return SwapSnapshot(used: swap.usedGB, total: swap.totalGB)
        }
    }

    func load(maxAge: TimeInterval) async -> LoadSnapshot {
        await loadCache.value(maxAge: maxAge) {
            guard let load = SystemInfo.loadAverages else { return LoadSnapshot(l1: 0, l5: 0, l15: 0) }
            return LoadSnapshot(l1: load.l1, l5: load.l5, l15: load.l15)
        }
    }

    func processes(limit: Int, maxAge: TimeInterval) async -> StatsParsers.ProcessTable {
        // Cachear todas las filas permite compartir ps incluso con límites distintos.
        let table = await processCache.value(maxAge: maxAge) {
            StatsParsers.processTable(
                fromPS: await self.run("/bin/ps", ["-A", "-o", "pid=,%cpu=,rss=,comm="]), limit: Int.max)
        }
        return StatsParsers.ProcessTable(count: table.count,
                                        topCPU: Array(table.topCPU.prefix(max(0, limit))),
                                        topRAM: Array(table.topRAM.prefix(max(0, limit))))
    }

    func batteryCycles(maxAge: TimeInterval) async -> Int {
        await cyclesCache.value(maxAge: maxAge) {
            StatsParsers.cycleCount(fromIoreg: await self.run("/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"]))
        }
    }

    func uptime() async -> String {
        guard let boot = SystemInfo.bootTime else { return "" }
        return StatsParsers.formatUptime(Date().timeIntervalSince(boot))
    }

    private func readCPUTicks() -> StatsParsers.CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3)
    }

    private func captureCPU() async -> CPUSnapshot {
        if let ticks = readCPUTicks() {
            let previous: StatsParsers.CPUTicks
            let current: StatsParsers.CPUTicks
            if let previousTicks {
                previous = previousTicks
                current = ticks
            } else {
                previous = ticks
                try? await Task.sleep(for: .milliseconds(250))
                guard let next = readCPUTicks() else { return await fallbackCPU() }
                current = next
            }
            previousTicks = current
            if let cpu = StatsParsers.cpuUsage(fromTicks: current, previous: previous) {
                lastCPU = CPUSnapshot(user: cpu.user, sys: cpu.sys, idle: cpu.idle)
            }
            return lastCPU
        }
        return await fallbackCPU()
    }

    private func fallbackCPU() async -> CPUSnapshot {
        previousTicks = nil
        let out = await run("/usr/bin/top", ["-l", "1", "-n", "0"])
        if let cpu = StatsParsers.cpuUsage(fromTop: out) {
            lastCPU = CPUSnapshot(user: cpu.user, sys: cpu.sys, idle: cpu.idle)
        } else {
            lastCPU = CPUSnapshot(user: 0, sys: 0, idle: 100)
        }
        return lastCPU
    }

    private func run(_ executable: String, _ args: [String]) async -> String {
        (try? await runShell(executable: executable, args: args))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

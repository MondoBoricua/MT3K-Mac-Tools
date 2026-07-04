// Parsers puros de stats — ver doc del enum. Compartidos por StatsState y MenuBarBridge.
import Foundation

/// Parsers puros extraídos para poder testearlos sin ejecutar comandos reales.
/// Compartidos entre StatsState (Stats pane) y MenuBarBridge (popover).
enum StatsParsers {
    /// Cuenta de ciclos desde la salida de `ioreg -rn AppleSmartBattery`.
    /// Exige la key exacta "CycleCount": el substring aparece también en
    /// "DesignCycleCount9C" (~1000), que antes sobreescribía el valor real.
    static func cycleCount(fromIoreg raw: String) -> Int {
        for line in raw.split(whereSeparator: \.isNewline) {
            if line.contains("\"CycleCount\"") {
                let digits = line.filter { $0.isNumber }
                return Int(digits) ?? 0
            }
        }
        return 0
    }

    /// Línea "CPU usage: X% user, Y% sys, Z% idle" de `top -l 1 -n 0`.
    static func cpuUsage(fromTop raw: String) -> (user: Double, sys: Double, idle: Double)? {
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.hasPrefix("CPU usage:") else { continue }
            guard let match = line.range(of: #"([0-9.]+)% user, ([0-9.]+)% sys, ([0-9.]+)% idle"#,
                                         options: .regularExpression) else { continue }
            let nums = String(line[match])
                .replacingOccurrences(of: "%", with: " ")
                .components(separatedBy: CharacterSet(charactersIn: " ,"))
                .compactMap(Double.init)
            if nums.count >= 3 {
                return (user: nums[0], sys: nums[1], idle: nums[2])
            }
        }
        return nil
    }

    struct VMStatMemory {
        var appGB: Double = 0
        var wiredGB: Double = 0
        var compressedGB: Double = 0
        var usedGB: Double { appGB + wiredGB + compressedGB }
    }

    /// Memoria usada desde la salida de `vm_stat` (page size autodetectado; default 16384 en Apple Silicon).
    static func memory(fromVMStat raw: String) -> VMStatMemory {
        let pageSize: Double = {
            if let line = raw.split(whereSeparator: \.isNewline).first(where: { $0.contains("page size of") }),
               let match = String(line).range(of: #"page size of (\d+)"#, options: .regularExpression) {
                return Double(String(line[match]).filter(\.isNumber)) ?? 16384
            }
            return 16384
        }()

        func pages(_ key: String) -> Double {
            for line in raw.split(whereSeparator: \.isNewline) where line.contains(key) {
                return Double(line.filter { $0.isNumber }) ?? 0
            }
            return 0
        }

        let gb = 1_073_741_824.0
        return VMStatMemory(
            appGB: pages("Pages active") * pageSize / gb,
            wiredGB: pages("Pages wired down") * pageSize / gb,
            compressedGB: pages("Pages occupied by compressor") * pageSize / gb
        )
    }

    /// "vm.swapusage: total = 2048.00M  used = 0.00M ..." → GB.
    static func swapGB(fromSysctl raw: String) -> (used: Double, total: Double)? {
        guard let match = raw.range(of: #"total\s*=\s*([\d.]+)M\s+used\s*=\s*([\d.]+)M"#,
                                    options: .regularExpression) else { return nil }
        let nums = String(raw[match])
            .components(separatedBy: CharacterSet(charactersIn: "=M "))
            .compactMap(Double.init)
        guard nums.count >= 2 else { return nil }
        return (used: nums[1] / 1024, total: nums[0] / 1024)
    }

    /// Primera fila de datos de `df -k <path>` → GB + % usado.
    static func disk(fromDF raw: String) -> (freeGB: Double, totalGB: Double, usedPercent: Double)? {
        for line in raw.split(whereSeparator: \.isNewline) {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 4,
                  let totalKB = Double(cols[1]),
                  let usedKB = Double(cols[2]),
                  let freeKB = Double(cols[3]) else { continue }
            return (
                freeGB: freeKB / 1_048_576.0,
                totalGB: totalKB / 1_048_576.0,
                // used/(used+free), no used/total: en APFS el total incluye espacio
                // purgeable/snapshot que df no reporta como usable.
                usedPercent: (usedKB / max(usedKB + freeKB, 1)) * 100
            )
        }
        return nil
    }

    /// "{ 1.23 2.34 3.45 }" de `sysctl -n vm.loadavg`.
    static func loadAverages(fromSysctl raw: String) -> (l1: Double, l5: Double, l15: Double)? {
        let nums = raw
            .components(separatedBy: CharacterSet(charactersIn: "{} \n\t"))
            .compactMap(Double.init)
        guard nums.count >= 3 else { return nil }
        return (l1: nums[0], l5: nums[1], l15: nums[2])
    }
}

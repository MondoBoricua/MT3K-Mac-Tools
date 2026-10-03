import Foundation
import Darwin

enum SystemInfo {
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    // Computed on every read: the kernel adjusts kern.boottime when the wall clock steps
    // (NTP, deep sleep), so a cached value would drift from the uptime macOS reports.
    static var bootTime: Date? {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000)
    }

    static var swapUsage: (usedGB: Double, totalGB: Double)? {
        var value = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &value, &size, nil, 0) == 0 else { return nil }
        return (Double(value.xsu_used) / 1_073_741_824, Double(value.xsu_total) / 1_073_741_824)
    }

    static var loadAverages: (l1: Double, l5: Double, l15: Double)? {
        var values = [Double](repeating: 0, count: 3)
        guard getloadavg(&values, 3) == 3 else { return nil }
        return (values[0], values[1], values[2])
    }

    static var thermalLevel: (state: Int, label: String) {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return (0, "Nominal")
        case .fair: return (1, "Fair")
        case .serious: return (2, "Serious")
        case .critical: return (3, "Critical")
        @unknown default: return (0, "Nominal")
        }
    }

    static var memoryPressure: (label: String, color: String) {
        var value: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &size, nil, 0) == 0 else {
            return ("Normal", "green")
        }
        switch value {
        case 2: return ("Warning", "orange")
        case 4: return ("Critical", "red")
        default: return ("Normal", "green")
        }
    }
}

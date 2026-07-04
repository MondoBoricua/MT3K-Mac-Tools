import Foundation

struct GPUUsageReading: Sendable {
    let devicePercent: Double
    let rendererPercent: Double
    let tilerPercent: Double
    let memoryGB: Double
}

enum GPUUsageReader {
    static func read() async -> GPUUsageReading? {
        guard let output = try? await runShell(executable: "/usr/sbin/ioreg", args: ["-r", "-c", "AGXAccelerator", "-l"]) else {
            return nil
        }

        guard let device = number(after: "\"Device Utilization %\"=", in: output) else {
            return nil
        }

        let renderer = number(after: "\"Renderer Utilization %\"=", in: output) ?? 0
        let tiler = number(after: "\"Tiler Utilization %\"=", in: output) ?? 0
        let memoryBytes = number(after: "\"In use system memory\"=", in: output) ?? 0

        return GPUUsageReading(
            devicePercent: min(max(device, 0), 100),
            rendererPercent: min(max(renderer, 0), 100),
            tilerPercent: min(max(tiler, 0), 100),
            memoryGB: memoryBytes / 1_073_741_824.0
        )
    }

    private static func number(after marker: String, in text: String) -> Double? {
        guard let range = text.range(of: marker) else { return nil }
        let tail = text[range.upperBound...]
        let value = tail.prefix { $0.isNumber || $0 == "." }
        return Double(value)
    }
}

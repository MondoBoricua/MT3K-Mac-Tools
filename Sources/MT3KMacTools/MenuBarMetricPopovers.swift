// Menu bar — medidores compactos (CompactMenuMetric) y popovers de métricas.
import SwiftUI
import AppKit

enum CompactMenuMetric: Hashable {
    case disk
    case cpu
    case gpu
    case ram

    var title: String {
        switch self {
        case .disk: return "SSD"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .ram: return "RAM"
        }
    }

    var symbol: String {
        switch self {
        case .disk: return "internaldrive.fill"
        case .cpu: return "cpu.fill"
        case .gpu: return "display"
        case .ram: return "memorychip.fill"
        }
    }
}

struct CompactMetricMenuLabel: View {
    @EnvironmentObject var bridge: MenuBarBridge
    let metric: CompactMenuMetric

    var body: some View {
        Image(nsImage: labelImage)
            .renderingMode(.original)
            .accessibilityLabel("\(metric.title) \(value)")
    }

    private var value: String {
        switch metric {
        case .disk:
            guard bridge.diskTotalGB > 0 else { return "--%" }
            return "\(Int(bridge.diskUsedPercent.rounded()))%"
        case .cpu:
            return "\(Int(bridge.cpuTotal.rounded()))%"
        case .gpu:
            guard !bridge.gpuUsagePercent.isNaN else { return "--%" }
            return "\(Int(bridge.gpuUsagePercent.rounded()))%"
        case .ram:
            guard bridge.ramTotalGB > 0 else { return "--%" }
            let percent = (bridge.ramUsedGB / max(bridge.ramTotalGB, 1)) * 100
            return "\(Int(percent.rounded()))%"
        }
    }

    private var color: Color {
        switch metric {
        case .disk:
            if bridge.diskUsedPercent > 90 { return .red }
            if bridge.diskUsedPercent > 80 { return .orange }
            return .primary
        case .cpu:
            if bridge.cpuTotal > 85 { return .red }
            if bridge.cpuTotal > 65 { return .orange }
            return .primary
        case .gpu:
            guard !bridge.gpuUsagePercent.isNaN else { return .secondary }
            if bridge.gpuUsagePercent > 85 { return .red }
            if bridge.gpuUsagePercent > 65 { return .orange }
            return .primary
        case .ram:
            guard bridge.ramTotalGB > 0 else { return .secondary }
            let percent = (bridge.ramUsedGB / max(bridge.ramTotalGB, 1)) * 100
            if percent > 90 { return .red }
            if percent > 80 { return .orange }
            return .primary
        }
    }

    private var nsColor: NSColor {
        switch metric {
        case .disk:
            if bridge.diskUsedPercent > 90 { return .systemRed }
            if bridge.diskUsedPercent > 80 { return .systemOrange }
            return .labelColor
        case .cpu:
            if bridge.cpuTotal > 85 { return .systemRed }
            if bridge.cpuTotal > 65 { return .systemOrange }
            return .labelColor
        case .gpu:
            guard !bridge.gpuUsagePercent.isNaN else { return .secondaryLabelColor }
            if bridge.gpuUsagePercent > 85 { return .systemRed }
            if bridge.gpuUsagePercent > 65 { return .systemOrange }
            return .labelColor
        case .ram:
            guard bridge.ramTotalGB > 0 else { return .secondaryLabelColor }
            let percent = (bridge.ramUsedGB / max(bridge.ramTotalGB, 1)) * 100
            if percent > 90 { return .systemRed }
            if percent > 80 { return .systemOrange }
            return .labelColor
        }
    }

    private var labelImage: NSImage {
        let titleFont = NSFont.systemFont(ofSize: 7, weight: .light)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let width = max(
            textWidth(metric.title, font: titleFont),
            textWidth(value, font: valueFont)
        ).rounded(.up) + 6
        let size = NSSize(width: max(26, width), height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .center
            let valueStyle = NSMutableParagraphStyle()
            valueStyle.alignment = .center

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: titleStyle
            ]
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: nsColor,
                .paragraphStyle: valueStyle
            ]

            NSAttributedString(string: metric.title, attributes: titleAttributes)
                .draw(with: NSRect(x: 0, y: 12.5, width: rect.width, height: 8))
            NSAttributedString(string: value, attributes: valueAttributes)
                .draw(with: NSRect(x: 0, y: 1, width: rect.width, height: 14))
            return true
        }
        image.isTemplate = false
        return image
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct CompactMetricMenuContent: View {
    @EnvironmentObject var bridge: MenuBarBridge
    let metric: CompactMenuMetric

    @ViewBuilder
    var body: some View {
        switch metric {
        case .ram:
            RAMMetricPopover()
                .environmentObject(bridge)
        case .cpu:
            CPUMetricPopover()
                .environmentObject(bridge)
        case .disk:
            DiskMetricPopover()
                .environmentObject(bridge)
        case .gpu:
            GPUMetricPopover()
                .environmentObject(bridge)
        }
    }
}

private struct RAMMetricPopover: View {
    @EnvironmentObject var bridge: MenuBarBridge

    private var usedPercent: Double {
        guard bridge.ramTotalGB > 0 else { return 0 }
        return (bridge.ramUsedGB / bridge.ramTotalGB) * 100
    }

    var body: some View {
        MetricPopoverFrame(title: "RAM", symbol: "memorychip.fill") {
            HStack(spacing: 20) {
                MiniGauge(value: usedPercent, title: "Pressure", color: Theme.green)
                MultiRingMeter(
                    center: "\(Int(usedPercent.rounded()))%",
                    segments: [
                        .init(value: bridge.ramAppGB, total: bridge.ramTotalGB, color: Theme.blue),
                        .init(value: bridge.ramWiredGB, total: bridge.ramTotalGB, color: Theme.amber),
                        .init(value: bridge.ramCompressedGB, total: bridge.ramTotalGB, color: Theme.accent),
                        .init(value: bridge.ramFreeGB, total: bridge.ramTotalGB, color: Color.secondary.opacity(0.5))
                    ],
                    size: 96
                )
            }
            SectionTitle("Usage history")
            HistoryArea(values: bridge.ramHistory, color: Theme.blue, height: 78)
            SectionTitle("Details")
            MetricRows(rows: [
                .plain("Used:", formatGB(bridge.ramUsedGB)),
                .swatch("App:", formatGB(bridge.ramAppGB), Theme.blue),
                .swatch("Wired:", formatGB(bridge.ramWiredGB), Theme.amber),
                .swatch("Compressed:", formatGB(bridge.ramCompressedGB), Theme.accent),
                .swatch("Free:", formatGB(bridge.ramFreeGB), Color.secondary.opacity(0.6)),
                .plain("Swap:", bridge.swapUsedGB <= 0 ? "Zero KB" : formatGB(bridge.swapUsedGB))
            ])
            ProcessList(title: "Top processes", samples: bridge.topRAM)
        }
        .task { await bridge.refresh(mode: .full) }
    }
}

private struct CPUMetricPopover: View {
    @EnvironmentObject var bridge: MenuBarBridge

    var body: some View {
        MetricPopoverFrame(title: "CPU", symbol: "cpu.fill") {
            HStack(spacing: 18) {
                MiniGauge(value: bridge.cpuTempC.isNaN ? 0 : min(100, bridge.cpuTempC), title: tempText, color: Theme.blue)
                MultiRingMeter(
                    center: "\(Int(bridge.cpuTotal.rounded()))%",
                    segments: [
                        .init(value: bridge.cpuSys, total: 100, color: Theme.accent),
                        .init(value: bridge.cpuUser, total: 100, color: Theme.blue),
                        .init(value: bridge.cpuIdle, total: 100, color: Color.secondary.opacity(0.45))
                    ],
                    size: 96
                )
                MiniGauge(value: min(100, bridge.loadAvg1 * 10), title: String(format: "%.2f", bridge.loadAvg1), color: Theme.blue)
            }
            SectionTitle("Usage history")
            HistoryArea(values: bridge.cpuHistory, color: Theme.blue, height: 78)
            SectionTitle("Details")
            MetricRows(rows: [
                .swatch("System:", String(format: "%.0f%%", bridge.cpuSys), Theme.accent),
                .swatch("User:", String(format: "%.0f%%", bridge.cpuUser), Theme.blue),
                .swatch("Idle:", String(format: "%.0f%%", bridge.cpuIdle), Color.secondary.opacity(0.6)),
                .plain("Uptime:", bridge.uptime.isEmpty ? "—" : bridge.uptime)
            ])
            SectionTitle("Average load")
            MetricRows(rows: [
                .plain("1 minute:", String(format: "%.2f", bridge.loadAvg1)),
                .plain("5 minutes:", String(format: "%.2f", bridge.loadAvg5)),
                .plain("15 minutes:", String(format: "%.2f", bridge.loadAvg15))
            ])
            ProcessList(title: "Top processes", samples: bridge.topCPU)
        }
        .task { await bridge.refresh(mode: .full) }
    }

    private var tempText: String {
        guard !bridge.cpuTempC.isNaN else { return "—" }
        return String(format: "%.0f°", bridge.cpuTempC)
    }
}

private struct DiskMetricPopover: View {
    @EnvironmentObject var bridge: MenuBarBridge

    private var usedGB: Double {
        max(0, bridge.diskTotalGB - bridge.diskFreeGB)
    }

    var body: some View {
        MetricPopoverFrame(title: "Disk", symbol: "internaldrive.fill") {
            DiskCard(
                name: "Macintosh HD",
                usedPercent: bridge.diskUsedPercent,
                freeGB: bridge.diskFreeGB,
                totalGB: bridge.diskTotalGB,
                history: bridge.diskHistory
            )
            SectionTitle("Details")
            MetricRows(rows: [
                .plain("Used:", formatGB(usedGB)),
                .plain("Free:", formatGB(bridge.diskFreeGB)),
                .plain("Total:", formatGB(bridge.diskTotalGB)),
                .plain("Capacity:", String(format: "%.0f%% used", bridge.diskUsedPercent))
            ])
            ProcessList(title: "Top processes", samples: bridge.topRAM)
        }
        .task { await bridge.refresh(mode: .full) }
    }
}

private struct GPUMetricPopover: View {
    @EnvironmentObject var bridge: MenuBarBridge

    var body: some View {
        MetricPopoverFrame(title: "GPU", symbol: "display") {
            MultiRingMeter(
                center: bridge.gpuUsagePercent.isNaN ? "—" : "\(Int(bridge.gpuUsagePercent.rounded()))%",
                segments: [
                    .init(value: bridge.gpuRendererPercent.isNaN ? 0 : bridge.gpuRendererPercent, total: 100, color: Theme.blue),
                    .init(value: bridge.gpuTilerPercent.isNaN ? 0 : bridge.gpuTilerPercent, total: 100, color: Theme.amber),
                    .init(value: max(0, 100 - (bridge.gpuUsagePercent.isNaN ? 0 : bridge.gpuUsagePercent)), total: 100, color: Color.secondary.opacity(0.45))
                ],
                size: 96
            )
            SectionTitle("Details")
            MetricRows(rows: [
                .plain("Usage:", bridge.gpuUsagePercent.isNaN ? "No data" : String(format: "%.0f%%", bridge.gpuUsagePercent)),
                .swatch("Renderer:", bridge.gpuRendererPercent.isNaN ? "—" : String(format: "%.0f%%", bridge.gpuRendererPercent), Theme.blue),
                .swatch("Tiler:", bridge.gpuTilerPercent.isNaN ? "—" : String(format: "%.0f%%", bridge.gpuTilerPercent), Theme.amber),
                .plain("Memory:", bridge.gpuMemoryGB <= 0 ? "—" : formatGB(bridge.gpuMemoryGB))
            ])
        }
        .task { await bridge.refresh(mode: .full) }
    }
}

private struct MetricPopoverFrame<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 11) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(title)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(16)
        }
        .frame(width: 320, height: 560)
        .background(.regularMaterial)
    }
}

private struct RingSegment: Identifiable {
    let id = UUID()
    let value: Double
    let total: Double
    let color: Color
}

private struct MultiRingMeter: View {
    let center: String
    let segments: [RingSegment]
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 11)
            ForEach(segmentOffsets, id: \.segment.id) { item in
                Circle()
                    .trim(from: item.start, to: item.end)
                    .stroke(item.segment.color, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text(center)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }

    private var segmentOffsets: [(segment: RingSegment, start: Double, end: Double)] {
        var cursor = 0.0
        return segments.map { segment in
            let fraction = max(0, min(1, segment.value / max(segment.total, 0.01)))
            let start = cursor
            let end = min(1, cursor + fraction)
            cursor = end
            return (segment, start, end)
        }
    }
}

private struct MiniGauge: View {
    let value: Double
    let title: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(90))
            Circle()
                .trim(from: 0.15, to: 0.15 + (0.70 * max(0, min(100, value)) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(90))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 64, height: 64)
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }
}

private struct HistoryArea: View {
    let values: [Double]
    let color: Color
    var height: CGFloat = 112

    var body: some View {
        GeometryReader { proxy in
            let samples = values.isEmpty ? [0] : values
            let step = proxy.size.width / CGFloat(max(samples.count - 1, 1))
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height))
                    for (index, value) in samples.enumerated() {
                        let x = CGFloat(index) * step
                        let y = proxy.size.height * (1 - CGFloat(max(0, min(100, value)) / 100))
                        if index == 0 {
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(color.gradient)
            }
        }
        .frame(height: height)
    }
}

private struct MetricRowData: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let color: Color?

    static func plain(_ label: String, _ value: String) -> MetricRowData {
        MetricRowData(label: label, value: value, color: nil)
    }

    static func swatch(_ label: String, _ value: String, _ color: Color) -> MetricRowData {
        MetricRowData(label: label, value: value, color: color)
    }
}

private struct MetricRows: View {
    let rows: [MetricRowData]

    var body: some View {
        VStack(spacing: 5) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    if let color = row.color {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: 12, height: 12)
                    }
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(row.value)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }
}

private struct ProcessList: View {
    let title: String
    let samples: [ProcessSample]

    var body: some View {
        VStack(spacing: 7) {
            SectionTitle(title)
            HStack {
                Text("Process")
                Spacer()
                Text("Usage")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            ForEach(samples) { sample in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: "/bin/zsh"))
                        .resizable()
                        .frame(width: 13, height: 13)
                    Text(sample.name)
                        .lineLimit(1)
                    Spacer()
                    Text(sample.value)
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }
}

private struct DiskCard: View {
    let name: String
    let usedPercent: Double
    let freeGB: Double
    let totalGB: Double
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Circle().fill(Theme.blue).frame(width: 8, height: 8)
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                Spacer()
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            }
            HistoryArea(values: history, color: Theme.blue, height: 44)
            ProgressView(value: max(0, min(100, usedPercent)), total: 100)
                .tint(Theme.blue)
            HStack {
                Text(String(format: "%.1f GB of %.1f GB free", freeGB, totalGB))
                Spacer()
                Text(String(format: "%.0f%%", usedPercent))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10))
        .clipShape(.rect(cornerRadius: 8))
    }
}

private func formatGB(_ value: Double) -> String {
    if value < 0.01 { return "Zero KB" }
    return String(format: "%.2f GB", value)
}


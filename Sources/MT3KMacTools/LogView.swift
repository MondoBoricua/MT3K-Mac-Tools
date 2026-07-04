import SwiftUI
import AppKit

struct LogView: View {
    @EnvironmentObject var log: LogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Registro de operaciones").font(.headline)
                logSummary
                Spacer()
                Button("Copiar") { copyLogs() }
                    .buttonStyle(.borderless)
                    .foregroundColor(Theme.blue)
                    .font(.caption)
                    .disabled(log.entries.isEmpty)
                Button("Limpiar") { log.clear() }
                    .buttonStyle(.borderless)
                    .foregroundColor(Theme.textSecondary)
                    .font(.caption)
                    .disabled(log.entries.isEmpty)
            }
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(log.entries) { e in
                            HStack(alignment: .top, spacing: 6) {
                                Text("[\(e.timeString)]")
                                    .foregroundColor(Theme.textSecondary)
                                Text(e.message)
                                    .foregroundColor(color(for: e.level))
                                Spacer(minLength: 0)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .id(e.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .frame(height: 160)
                .background(Theme.bgDark)
                .cornerRadius(8)
                .onChange(of: log.entries.count) { _, _ in
                    if let last = log.entries.last?.id {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var logSummary: some View {
        HStack(spacing: 6) {
            miniBadge("\(count(.success)) ok", color: Theme.green)
            miniBadge("\(count(.warn)) warn", color: Theme.amber)
            miniBadge("\(count(.error)) err", color: Theme.accent)
        }
    }

    private func miniBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func count(_ level: LogStore.Level) -> Int {
        log.entries.filter { $0.level == level }.count
    }

    private func copyLogs() {
        let text = log.entries.map { "[\($0.timeString)] \($0.level.rawValue): \($0.message)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func color(for level: LogStore.Level) -> Color {
        switch level {
        case .info: return Theme.blue
        case .success: return Theme.green
        case .warn: return Theme.amber
        case .error: return Theme.accent
        }
    }
}

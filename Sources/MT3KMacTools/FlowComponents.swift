// MT3K Flow — componentes de UI compartidos (paneles, cards, badges).
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import Security
import SwiftUI

struct FlowIconMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = MT3KFlowAssets.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.72, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
    }
}

struct FlowPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border.opacity(0.45)))
    }
}

struct FlowPermissionCard: View {
    let title: String
    let detail: String
    let symbol: String
    let state: FlowPermissionState
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .bold))
                    Text(detail).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button(state.ok ? "Revisar" : "Pedir") { request() }
                    .buttonStyle(.bordered)
                Button("Settings") { openSettings() }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var color: Color {
        switch state {
        case .granted: return Theme.green
        case .denied: return .red
        case .prompt: return Theme.amber
        case .unknown: return Theme.textSecondary
        }
    }
}

struct FlowActionButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .background(color.opacity(0.14))
        .clipShape(.rect(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.35)))
    }
}

struct FlowStepCard: View {
    let title: String
    let detail: String
    let symbol: String
    let ready: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(ready ? Theme.green : Theme.amber)
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Color.white.opacity(0.045))
        .clipShape(.rect(cornerRadius: 10))
    }
}

struct FlowHistoryRow: View {
    let entry: FlowHistoryEntry
    let isSelected: Bool
    @Binding var correctionText: String
    let select: () -> Void
    let save: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: select) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.green : Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.cleaned)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(entry.createdLabel) · \(String(format: "%.1f s", entry.durationSecs))")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isSelected {
                Text("Raw: \(entry.raw)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)

                TextEditor(text: $correctionText)
                    .font(.system(size: 13))
                    .frame(minHeight: 72)
                    .scrollContentBackground(.hidden)
                    .background(Color.black.opacity(0.16))
                    .clipShape(.rect(cornerRadius: 8))

                HStack(spacing: 8) {
                    Button("Guardar corrección") { save() }
                        .buttonStyle(.borderedProminent)
                    Button("Eliminar", role: .destructive) { delete() }
                        .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(isSelected ? 0.075 : 0.045))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Theme.accent.opacity(0.55) : Theme.border.opacity(0.35)))
    }
}

struct FlowTagCloud: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.blue.opacity(0.12))
                    .foregroundStyle(Theme.textSecondary)
                    .clipShape(.rect(cornerRadius: 7))
            }
        }
    }
}

struct FlowRoadmapRow: View {
    let text: String
    let done: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Theme.green : Theme.textSecondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(done ? .primary : Theme.textSecondary)
        }
    }
}

struct FlowStatusBadge: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(color)
            .background(color.opacity(0.13))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.35)))
    }
}

struct FlowMiniPermission: View {
    let title: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
            Text(title)
        }
        .font(.caption2.bold())
        .foregroundStyle(ok ? Theme.green : Theme.amber)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 6))
    }
}

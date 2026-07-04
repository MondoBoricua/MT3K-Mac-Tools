// Displays — vistas del pane y contenido del menu bar.
import AppKit
import CoreGraphics
import SwiftUI

struct DisplayManagementSection: View {
    @ObservedObject var state: DisplayControlState

    var body: some View {
        SystemPanel(title: "Displays", symbol: "display") {
            header
            LazyVStack(spacing: 10) {
                ForEach(state.displays) { display in
                    DisplayControlCard(display: display, state: state)
                }
                ForEach(state.disconnectedDisplays) { display in
                    DisconnectedDisplayCard(display: display, state: state)
                }
            }
            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .task { await state.refresh() }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                displayCountBadges
                Spacer(minLength: 12)
                displayActions
            }
            VStack(alignment: .leading, spacing: 10) {
                displayCountBadges
                displayActions
            }
        }
    }

    private var displayCountBadges: some View {
        HStack(spacing: 8) {
            DisplayCountBadge(value: state.displays.count, label: "pantallas", color: Theme.blue)
            DisplayCountBadge(value: state.enabledDisplaysCount, label: "activas", color: Theme.green)
        }
    }

    private var displayActions: some View {
        HStack(spacing: 8) {
            SystemActionButton(title: "Refrescar", symbol: "arrow.clockwise", color: Theme.blue, busy: state.loading) {
                Task { await state.refresh() }
            }
            .disabled(state.loading)
            SystemActionButton(title: "Ajustes", symbol: "gearshape.fill", color: Theme.blue) {
                state.openDisplaySettings()
            }
            SystemActionButton(title: "Dormir", symbol: "moon.zzz.fill", color: Theme.amber) {
                Task { await state.sleepDisplaysNow() }
            }
            SystemActionButton(title: "Color", symbol: "paintbrush.pointed.fill", color: Theme.green) {
                Task { await state.restoreAllSoftwareBrightness() }
            }
            if !state.hasDisplayplacer {
                SystemActionButton(title: "Instalar", symbol: "arrow.down.circle.fill", color: Theme.blue) {
                    state.installDisplayplacerInTerminal()
                }
            }
        }
    }
}

private struct DisplayCountBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption.bold())
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 104, alignment: .center)
        .background(color.opacity(0.13))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.36)))
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct DisplayControlCard: View {
    let display: DisplaySnapshot
    @ObservedObject var state: DisplayControlState
    @State private var selectedModeID: String
    @State private var brightness: Double

    init(display: DisplaySnapshot, state: DisplayControlState) {
        self.display = display
        self.state = state
        let currentMode = display.modes.first {
            $0.width == display.width && $0.height == display.height && abs($0.refreshRate - display.refreshRate) < 1
        }
        _selectedModeID = State(initialValue: currentMode?.id ?? display.modes.first?.id ?? "")
        _brightness = State(initialValue: display.softwareBrightness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.title3)
                    .foregroundColor(display.isActive ? Theme.blue : Theme.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(display.name).font(.headline)
                        if display.isMain { BadgePill(text: "Main", color: Theme.textSecondary) }
                        if display.isBuiltin { BadgePill(text: "Built-in", color: Theme.blue) }
                    }
                    Text("\(display.modeSummary) · \(display.pixelWidth)x\(display.pixelHeight) px")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { display.isActive },
                    set: { _ in Task { await state.toggleDisplayConnection(display.id) } }
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help("Desconectar/reconectar esta pantalla.")
            }

            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(Theme.amber)
                    .frame(width: 24)
                Slider(value: $brightness, in: 0.0...1.0) {
                    Text("Brightness")
                } minimumValueLabel: {
                    Text("0%").font(.caption2).foregroundColor(Theme.textSecondary)
                } maximumValueLabel: {
                    Text("100%").font(.caption2).foregroundColor(Theme.textSecondary)
                }
                .onChange(of: brightness) {
                    state.setSoftwareBrightness(brightness, for: display.id)
                }
                Text("\(Int(brightness * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 42, alignment: .trailing)
            }

            HStack(spacing: 12) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundColor(Theme.green)
                    .frame(width: 24)
                Picker("Resolución", selection: $selectedModeID) {
                    ForEach(display.modes) { mode in
                        Text(mode.title).tag(mode.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                .onChange(of: selectedModeID) {
                    Task { await state.setResolution(selectedModeID, for: display.id) }
                }
                Text("Actual: \(display.modeSummary)")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button {
                    state.restoreSoftwareBrightness(for: display.id)
                    brightness = 1.0
                } label: {
                    Label("Reset color", systemImage: "paintbrush")
                }
                .buttonStyle(.borderless)
                if display.isBuiltin {
                    Button {
                        Task { await state.applySayNoNotch(to: display.id) }
                    } label: {
                        Label("Say No Notch", systemImage: "rectangle.topthird.inset.filled")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .background(Theme.bgDark.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 8))
        .onChange(of: display.softwareBrightness) {
            brightness = display.softwareBrightness
        }
    }
}

private struct DisconnectedDisplayCard: View {
    let display: DisplayplacerDisplayRecord
    @ObservedObject var state: DisplayControlState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundColor(Theme.amber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(display.name).font(.headline)
                Text("\(display.width)x\(display.height) · \(Int(display.refreshRate)) Hz · desconectada")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            SystemActionButton(title: "Reconectar", symbol: "display.2", color: Theme.green) {
                Task { _ = await state.reconnectDisplay(display) }
            }
        }
        .padding(12)
        .background(Theme.amber.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.amber.opacity(0.35)))
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct DisplayMenuBarContent: View {
    @EnvironmentObject var state: DisplayControlState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            ForEach(state.displays) { display in
                compactDisplay(display)
            }
            ForEach(state.disconnectedDisplays) { display in
                compactDisconnectedDisplay(display)
            }
            Divider()
            actions
            if !state.statusMessage.isEmpty {
                Text(state.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Divider()
            footer
        }
        .padding(10)
        .frame(width: 340)
        .task { await state.refresh() }
    }

    private func compactDisconnectedDisplay(_ display: DisplayplacerDisplayRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .frame(width: 24)
                .foregroundColor(Theme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text("\(display.width)x\(display.height) · desconectada")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { false },
                set: { _ in Task { _ = await state.reconnectDisplay(display) } }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
                .scaleEffect(0.72)
                .help("Reconectar esta pantalla con displayplacer.")
        }
        .padding(10)
        .background(Theme.amber.opacity(0.10))
        .clipShape(.rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "display").foregroundColor(Theme.blue)
            Text("Displays").bold()
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private func compactDisplay(_ display: DisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .frame(width: 24)
                    .foregroundColor(display.isActive ? Theme.blue : .secondary)
                Text(display.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                if display.isMain {
                    Text("M")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.25))
                        .clipShape(Capsule())
                }
                Spacer()
                Text(display.modeSummary)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                Toggle("", isOn: Binding(
                    get: { display.isActive },
                    set: { _ in Task { await state.toggleDisplayConnection(display.id) } }
                ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.72)
                    .help("Desconectar/reconectar esta pantalla.")
            }

            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(Theme.amber)
                    .frame(width: 24)
                Slider(
                    value: Binding(
                        get: { display.softwareBrightness },
                        set: { state.setSoftwareBrightness($0, for: display.id) }
                    ),
                    in: 0.0...1.0
                )
                Text("\(Int(display.softwareBrightness * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundColor(Theme.green)
                    .frame(width: 24)
                Picker(
                    "Resolution",
                    selection: Binding(
                        get: { currentModeID(for: display) },
                        set: { modeID in
                            Task { await state.setResolution(modeID, for: display.id) }
                        }
                    )
                ) {
                    ForEach(display.modes) { mode in
                        Text(mode.title).tag(mode.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
                if display.isBuiltin {
                    Button {
                        Task { await state.applySayNoNotch(to: display.id) }
                    } label: {
                        Label("No Notch", systemImage: "rectangle.topthird.inset.filled")
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    state.restoreSoftwareBrightness(for: display.id)
                } label: {
                    Label("Reset", systemImage: "paintbrush")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func currentModeID(for display: DisplaySnapshot) -> String {
        display.modes.first {
            $0.width == display.width &&
            $0.height == display.height &&
            abs($0.refreshRate - display.refreshRate) < 1
        }?.id ?? display.modes.first?.id ?? ""
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                state.openDisplaySettings()
            } label: {
                Label("Ajustes", systemImage: "gearshape.fill")
            }
            .buttonStyle(.borderless)
            Button {
                Task { await state.sleepDisplaysNow() }
            } label: {
                Label("Sleep", systemImage: "moon.zzz.fill")
            }
            .buttonStyle(.borderless)
            Button {
                Task { await state.reconnectAllDisplays() }
            } label: {
                Label("Reconectar", systemImage: "display.2")
            }
            .buttonStyle(.borderless)
            Spacer()
            Button {
                Task { await state.restoreAllSoftwareBrightness() }
            } label: {
                Label("Restaurar", systemImage: "paintbrush.pointed.fill")
            }
            .buttonStyle(.borderless)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "display")
                .font(.caption2)
                .foregroundColor(Theme.blue)
            Text("Displays · MT3K Mac Tools")
                .font(.caption2.bold())
                .foregroundColor(.secondary)
            Spacer()
            if !state.hasDisplayplacer {
                Button {
                    state.installDisplayplacerInTerminal()
                } label: {
                    Text("Instalar displayplacer")
                }
                .font(.caption2)
                .buttonStyle(.borderless)
            }
        }
    }
}

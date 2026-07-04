// MT3K Flow — HUD flotante que sigue el cursor durante la dictado.
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import Security
import SwiftUI

enum FlowHUDMode {
    case idle
    case recording
    case processing
}

@MainActor
final class FlowCursorHUDModel: ObservableObject {
    @Published var level: Double = 0
    @Published var mode: FlowHUDMode = .idle
}

@MainActor
final class FlowCursorHUDController {
    private let model = FlowCursorHUDModel()
    private var panel: NSPanel?
    private var followTimer: Timer?

    func show(level: Double, mode: FlowHUDMode) {
        ensurePanel()
        update(level: level, mode: mode)
        panel?.orderFrontRegardless()
        startFollowing()
    }

    func update(level: Double, mode: FlowHUDMode) {
        model.level = level
        model.mode = mode
        positionAtCursor()
    }

    func hide() {
        followTimer?.invalidate()
        followTimer = nil
        model.mode = .idle
        panel?.orderOut(nil)
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 46),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: FlowCursorHUDView(model: model))
        self.panel = panel
    }

    private func startFollowing() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.positionAtCursor()
            }
        }
    }

    private func positionAtCursor() {
        guard let panel else { return }
        let point = NSEvent.mouseLocation
        let size = panel.frame.size
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offsetX: CGFloat = 16
        let offsetY: CGFloat = -10
        let x = min(max(point.x + offsetX, frame.minX), frame.maxX - size.width)
        let y = min(max(point.y + offsetY, frame.minY), frame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

struct FlowCursorHUDView: View {
    @ObservedObject var model: FlowCursorHUDModel

    var body: some View {
        HStack(spacing: 8) {
            FlowIconMark(size: 28)
            waveform
            if model.mode == .processing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: model.mode == .processing ? 132 : 120, height: 46)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(modeColor.opacity(0.55), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 18))
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(modeColor)
                    .frame(width: 4, height: barHeight(index))
            }
        }
        .frame(width: 34, height: 24)
    }

    private var modeColor: Color {
        switch model.mode {
        case .idle: return Theme.textSecondary
        case .recording: return Theme.accent
        case .processing: return Theme.blue
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        if model.mode == .processing {
            return CGFloat([10, 16, 22, 16, 10][index])
        }
        let base = [8.0, 13.0, 18.0, 13.0, 8.0][index]
        return CGFloat(max(5, base + model.level * 16))
    }
}

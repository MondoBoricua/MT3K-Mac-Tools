import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        DisplayGammaController.restoreAll()
        DisplayDimmingOverlayController.shared.restoreAll()
    }
}

@main
struct MT3KMacToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var logStore = LogStore()
    @StateObject private var auth = AdminAuth()
    @StateObject private var brewState = BrewState()
    @StateObject private var installer = InstallCoordinator()
    @StateObject private var menuBarBridge = MenuBarBridge()
    @StateObject private var displayState = DisplayControlState()
    @StateObject private var flowState = FlowState()
    @StateObject private var loginItemState = LoginItemState()
    @StateObject private var batteryGuardState = BatteryGuardState()
    @AppStorage("menuBarEnabled") private var menuBarEnabled: Bool = true
    @AppStorage("displayMenuBarEnabled") private var displayMenuBarEnabled: Bool = true
    @AppStorage("flowMenuBarEnabled") private var flowMenuBarEnabled: Bool = false
    @AppStorage("menuMetricDiskEnabled") private var menuMetricDiskEnabled: Bool = false
    @AppStorage("menuMetricCPUEnabled") private var menuMetricCPUEnabled: Bool = false
    @AppStorage("menuMetricGPUEnabled") private var menuMetricGPUEnabled: Bool = false
    @AppStorage("menuMetricRAMEnabled") private var menuMetricRAMEnabled: Bool = false
    @AppStorage("batteryGuardEnabled") private var batteryGuardEnabled = false
    @AppStorage("batteryGuardLimit") private var batteryGuardLimit = 80.0
    @AppStorage("batteryGuardResumeBelow") private var batteryGuardResumeBelow = 75.0
    /// Fresh UUID per process launch — used as a view ID to guarantee the entire
    /// view tree is re-created on each launch (defeats any macOS window-state
    /// restoration that could otherwise reanimate stale row state).
    private let launchID = UUID().uuidString

    var body: some Scene {
        Window("MT3K Mac Tools", id: "main") {
            ContentView()
                .environmentObject(logStore)
                .environmentObject(auth)
                .environmentObject(brewState)
                .environmentObject(installer)
                .environmentObject(displayState)
                .environmentObject(menuBarBridge)
                .environmentObject(flowState)
                .environmentObject(loginItemState)
                .environmentObject(batteryGuardState)
                .task {
                    flowState.bootstrapFromUserDefaults()
                    await runBatteryGuardLoop()
                }
                .onChange(of: flowMenuBarEnabled) {
                    flowState.setFlowActive(flowMenuBarEnabled)
                }
                .frame(minWidth: 960, minHeight: 640)
                .preferredColorScheme(.dark)
                .id(launchID)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Re-verificar apps") {
                    Task { await brewState.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Mostrar logs") {
                    logStore.append("Logs visibles en el panel inferior.", level: .info)
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            CommandGroup(after: .help) {
                Button("Liberar sesión admin") {
                    auth.release()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarContent()
                .environmentObject(menuBarBridge)
                .environmentObject(loginItemState)
                .environmentObject(batteryGuardState)
                .task { menuBarBridge.startPolling() }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra(isInserted: $flowMenuBarEnabled) {
            FlowMenuBarContent()
                .environmentObject(flowState)
                .task { flowState.refreshPermissions() }
        } label: {
            FlowMenuBarLabel(isRecording: flowState.isRecording, permissionsReady: flowState.permissionsReady)
                .task {
                    flowState.bootstrapFromUserDefaults()
                }
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra("Caffeine", systemImage: "cup.and.saucer.fill", isInserted: caffeineMenuInserted) {
            CaffeineMenuBarContent()
                .environmentObject(menuBarBridge)
                .task { menuBarBridge.refreshCaffeineStatus() }
        }
        .menuBarExtraStyle(.window)

        MenuBarExtra("Displays", systemImage: "display", isInserted: $displayMenuBarEnabled) {
            DisplayMenuBarContent()
                .environmentObject(displayState)
        }
        .menuBarExtraStyle(.window)

        compactMetricExtra(.disk, isInserted: $menuMetricDiskEnabled)
        compactMetricExtra(.cpu, isInserted: $menuMetricCPUEnabled)
        compactMetricExtra(.gpu, isInserted: $menuMetricGPUEnabled)
        compactMetricExtra(.ram, isInserted: $menuMetricRAMEnabled)
    }

    private func compactMetricExtra(
        _ metric: CompactMenuMetric,
        isInserted: Binding<Bool>
    ) -> some Scene {
        MenuBarExtra(isInserted: isInserted) {
            CompactMetricMenuContent(metric: metric)
                .environmentObject(menuBarBridge)
        } label: {
            CompactMetricMenuLabel(metric: metric)
                .environmentObject(menuBarBridge)
                .task { menuBarBridge.startCompactPolling(interval: 15) }
        }
        .menuBarExtraStyle(.window)
    }

    /// Logo del app escalado para menu bar + badge dinámico de estado.
    /// Si hay críticos, mostramos el shield rojo encima del icono.
    @ViewBuilder
    private var menuBarLabel: some View {
        if let icon = Self.menuBarIcon {
            Image(nsImage: icon)
        } else {
            Image(systemName: scoreSymbol)
        }
    }

    private var caffeineMenuInserted: Binding<Bool> {
        Binding(
            get: { menuBarBridge.caffeinatePID != nil },
            set: { isInserted in
                if !isInserted, menuBarBridge.caffeinatePID != nil {
                    Task { await menuBarBridge.toggleCaffeine() }
                }
            }
        )
    }

    private var scoreSymbol: String {
        "wrench.adjustable.fill"
    }

    private func runBatteryGuardLoop() async {
        while !Task.isCancelled {
            await batteryGuardState.refresh()
            if batteryGuardEnabled {
                _ = await batteryGuardState.evaluateGuard(
                    limit: Int(batteryGuardLimit),
                    resumeBelow: Int(batteryGuardResumeBelow),
                    reason: "background"
                )
            }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// Carga MenuBarIcon.png (sprite hacker pet del usuario) con representaciones
    /// retina @1x/@2x/@3x. Fallback a AppIcon.icns si no se encuentra.
    static let menuBarIcon: NSImage? = {
        // Buscar MenuBarIcon.png + @2x/@3x para combinar en un NSImage con varias reps.
        let base = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png")
        let x2 = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png")
        let x3 = Bundle.main.url(forResource: "MenuBarIcon@3x", withExtension: "png")

        if let base, let baseImage = NSImage(contentsOf: base) {
            // Tamaño nominal en puntos (no en píxeles). El @2x/@3x cubren retina.
            baseImage.size = NSSize(width: 14, height: 22)
            if let x2, let rep2 = NSImage(contentsOf: x2)?.representations.first {
                baseImage.addRepresentation(rep2)
            }
            if let x3, let rep3 = NSImage(contentsOf: x3)?.representations.first {
                baseImage.addRepresentation(rep3)
            }
            return baseImage
        }

        // Fallback al AppIcon.icns.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return nil
    }()
}

private struct CaffeineMenuBarContent: View {
    @EnvironmentObject var bridge: MenuBarBridge
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(.orange)
                Text("Caffeine activo")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(caffeineMode)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let pid = bridge.caffeinatePID {
                    Text("PID \(pid)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()

            Button {
                Task { await bridge.toggleCaffeine() }
            } label: {
                Label("Detener Caffeine", systemImage: "stop.fill")
            }

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Abrir MT3K Mac Tools", systemImage: "macwindow")
            }
        }
        .padding(12)
        .frame(width: 230)
    }

    private var caffeineMode: String {
        bridge.caffeinateMode.isEmpty ? "Manteniendo el Mac despierto" : bridge.caffeinateMode
    }
}

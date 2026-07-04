// Displays — modelos, DisplayControlState y controllers (gamma, dimming, conexión).
import AppKit
import CoreGraphics
import SwiftUI

struct DisplaySnapshot: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let displayplacerID: String?
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    let isActive: Bool
    let isOnline: Bool
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let modes: [DisplayModeOption]
    var softwareBrightness: Double

    var modeSummary: String {
        let hz = refreshRate > 0 ? String(format: " · %.0f Hz", refreshRate) : ""
        return "\(width)x\(height)\(hz)"
    }

    var usesOverlayDimming: Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("sidecar") || lowercased.contains("ipad") || lowercased.contains("airplay")
    }
}

struct DisplayplacerDisplayRecord: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let configArgument: String
    let enabled: Bool
    let width: Int
    let height: Int
    let refreshRate: Double
    let isMain: Bool
    let modes: [DisplayplacerMode]
}

struct DisplayplacerMode: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let width: Int
    let height: Int
    let refreshRate: Double
    let colorDepth: Int
    let scaling: Bool
}

@_silgen_name("CGSConfigureDisplayEnabled")
private func CGSConfigureDisplayEnabled(
    _ config: CGDisplayConfigRef?,
    _ display: CGDirectDisplayID,
    _ enabled: Bool
) -> CGError

enum DisplayConnectionController {
    static func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        let changeError = CGSConfigureDisplayEnabled(config, displayID, enabled)
        guard changeError == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}

struct DisplayModeOption: Identifiable, Hashable {
    let id: String
    let width: Int
    let height: Int
    let refreshRate: Double
    let scaling: Bool?
    let colorDepth: Int?
    fileprivate let mode: CGDisplayMode?

    var title: String {
        let hz = refreshRate > 0 ? String(format: " · %.0f Hz", refreshRate) : ""
        let hidpi = scaling == true ? " · HiDPI" : ""
        return "\(width)x\(height)\(hz)\(hidpi)"
    }

    var displayplacerArgument: String? {
        guard mode == nil else { return nil }
        var parts = ["res:\(width)x\(height)"]
        if refreshRate > 0 { parts.append("hz:\(Int(refreshRate.rounded()))") }
        if let colorDepth { parts.append("color_depth:\(colorDepth)") }
        if let scaling { parts.append("scaling:\(scaling ? "on" : "off")") }
        return parts.joined(separator: " ")
    }

    static func == (lhs: DisplayModeOption, rhs: DisplayModeOption) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
final class DisplayControlState: ObservableObject {
    @Published var displays: [DisplaySnapshot] = []
    @Published var disconnectedDisplays: [DisplayplacerDisplayRecord] = []
    @Published var loading = false
    @Published var statusMessage = ""

    private let brightnessPrefix = "displaySoftwareBrightness."
    private let disconnectedKey = "displayplacerDisconnectedDisplays"

    var enabledDisplaysCount: Int {
        displays.filter(\.isActive).count
    }

    var hasDisplayplacer: Bool {
        displayplacerExecutable() != nil
    }

    func refresh() async {
        loading = true
        defer { loading = false }

        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = Array(repeating: CGDirectDisplayID(), count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        let displayplacerRecords = await readDisplayplacerRecords()

        displays = ids.map { snapshot(for: $0, displayplacerRecords: displayplacerRecords) }
        mergeDisconnectedRecords(displayplacerRecords)
        if statusMessage.isEmpty {
            statusMessage = displays.isEmpty ? "No se detectaron pantallas." : "\(displays.count) pantalla(s) detectada(s)."
        }
    }

    func setSoftwareBrightness(_ value: Double, for displayID: CGDirectDisplayID) {
        let clamped = min(max(value, 0.0), 1.0)
        if displays.first(where: { $0.id == displayID })?.usesOverlayDimming == true {
            DisplayDimmingOverlayController.shared.setBrightness(clamped, for: displayID)
            UserDefaults.standard.set(clamped, forKey: brightnessKey(displayID))
            updateBrightness(clamped, for: displayID)
            statusMessage = "Brillo overlay aplicado: \(Int(clamped * 100))%."
            return
        }
        guard DisplayGammaController.apply(brightness: clamped, to: displayID) else {
            statusMessage = "No se pudo ajustar el brillo software."
            return
        }
        UserDefaults.standard.set(clamped, forKey: brightnessKey(displayID))
        updateBrightness(clamped, for: displayID)
        statusMessage = "Brillo software aplicado: \(Int(clamped * 100))%."
    }

    func restoreSoftwareBrightness(for displayID: CGDirectDisplayID) {
        DisplayGammaController.restore(displayID)
        DisplayDimmingOverlayController.shared.restore(displayID)
        UserDefaults.standard.removeObject(forKey: brightnessKey(displayID))
        updateBrightness(1.0, for: displayID)
        statusMessage = "Color restaurado para la pantalla."
    }

    func toggleSoftwareDisplay(_ displayID: CGDirectDisplayID) {
        let current = displays.first(where: { $0.id == displayID })?.softwareBrightness ?? 1.0
        if current > 0.01 && displays.filter({ $0.softwareBrightness > 0.01 }).count <= 1 {
            statusMessage = "No apago la última pantalla visible desde la app."
            return
        }
        setSoftwareBrightness(current > 0.01 ? 0.0 : 1.0, for: displayID)
    }

    func toggleDisplayConnection(_ displayID: CGDirectDisplayID) async {
        guard let display = displays.first(where: { $0.id == displayID }) else {
            statusMessage = "Pantalla no encontrada."
            return
        }
        guard displays.filter(\.isActive).count > 1 || !display.isActive else {
            statusMessage = "No desconecto la última pantalla activa."
            return
        }
        rememberDisconnected(
            DisplayplacerDisplayRecord(
                id: "\(displayID)",
                name: display.name,
                configArgument: "",
                enabled: false,
                width: display.width,
                height: display.height,
                refreshRate: display.refreshRate,
                isMain: display.isMain,
                modes: []
            )
        )
        if DisplayConnectionController.setEnabled(false, displayID: displayID) {
            statusMessage = "\(display.name): desconectada."
            await refresh()
        } else {
            forgetDisconnected("\(displayID)")
            statusMessage = "No se pudo desconectar esta pantalla."
        }
    }

    func reconnectAllDisplays() async {
        let records = disconnectedDisplays
        guard !records.isEmpty else {
            statusMessage = "No hay pantallas desconectadas guardadas."
            return
        }
        for record in records {
            _ = await reconnectDisplay(record)
        }
        statusMessage = "Intenté reconectar \(records.count) pantalla(s)."
        await refresh()
    }

    func reconnectDisplay(_ record: DisplayplacerDisplayRecord) async -> Bool {
        var didReconnect = false
        if let displayID = CGDirectDisplayID(record.id) {
            didReconnect = DisplayConnectionController.setEnabled(true, displayID: displayID)
        }
        if !didReconnect {
            didReconnect = await runDisplayplacerArgument(
                record.configArgument.replacingOccurrences(of: "enabled:false", with: "enabled:true")
            )
        }
        if !didReconnect {
            didReconnect = await setDisplayConnectionWithDisplayplacer(record.id, enabled: true)
        }
        if didReconnect {
            forgetDisconnected(record.id)
        }
        await refresh()
        return didReconnect
    }

    func installDisplayplacerInTerminal() {
        do {
            let script = """
            #!/bin/zsh
            set -e
            echo "Instalando displayplacer..."
            brew install displayplacer
            echo
            echo "Listo. displayplacer instalado."
            read -k 1 "?Presiona cualquier tecla para cerrar..."
            """
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("mt3k-install-displayplacer-\(UUID().uuidString).command")
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try openInTerminal(scriptPath: url.path)
            statusMessage = "Abriendo Terminal para instalar displayplacer."
        } catch {
            statusMessage = "No se pudo abrir instalador: \(error.localizedDescription)"
        }
    }

    func restoreAllSoftwareBrightness() async {
        DisplayGammaController.restoreAll()
        DisplayDimmingOverlayController.shared.restoreAll()
        for display in displays {
            UserDefaults.standard.removeObject(forKey: brightnessKey(display.id))
        }
        await refresh()
        statusMessage = "ColorSync restaurado para todas las pantallas."
    }

    func setResolution(_ modeID: String, for displayID: CGDirectDisplayID) async {
        guard let display = displays.first(where: { $0.id == displayID }),
              let option = display.modes.first(where: { $0.id == modeID }) else {
            statusMessage = "Resolución no encontrada."
            return
        }
        if let argument = option.displayplacerArgument, let displayplacerID = display.displayplacerID {
            if await runDisplayplacerArgument("id:\(displayplacerID) \(argument) enabled:true") {
                statusMessage = "Resolución aplicada: \(option.title)."
                await refresh()
            } else {
                statusMessage = "displayplacer no pudo aplicar \(option.title)."
            }
            return
        }
        guard let coreGraphicsMode = option.mode else {
            statusMessage = "Resolución no aplicable sin displayplacer."
            return
        }

        let error = CGDisplaySetDisplayMode(displayID, coreGraphicsMode, nil)
        if error == .success {
            statusMessage = "Resolución aplicada: \(option.title)."
        } else {
            statusMessage = "macOS no permitió cambiar esa resolución (\(error.rawValue))."
        }
        await refresh()
    }

    func applySayNoNotch(to displayID: CGDirectDisplayID) async {
        guard let display = displays.first(where: { $0.id == displayID && $0.isBuiltin }) else {
            statusMessage = "Say No Notch solo aplica al display interno."
            return
        }
        guard let mode = display.modes
            .filter({ $0.width == 1512 && $0.height == 945 })
            .sorted(by: { $0.refreshRate > $1.refreshRate })
            .first else {
            statusMessage = "No encontré 1512x945 para este display."
            return
        }
        await setResolution(mode.id, for: displayID)
        statusMessage = "Say No Notch aplicado: \(mode.title)."
    }

    func stepResolution(for displayID: CGDirectDisplayID, direction: Int) async {
        guard let display = displays.first(where: { $0.id == displayID }),
              !display.modes.isEmpty else { return }
        let currentIndex = display.modes.firstIndex {
            $0.width == display.width && $0.height == display.height && abs($0.refreshRate - display.refreshRate) < 1
        } ?? display.modes.startIndex
        let nextIndex = min(max(currentIndex + direction, display.modes.startIndex), display.modes.index(before: display.modes.endIndex))
        await setResolution(display.modes[nextIndex].id, for: displayID)
    }

    func sleepDisplaysNow() async {
        _ = try? await runShell(executable: "/usr/bin/pmset", args: ["displaysleepnow"])
        statusMessage = "Pantallas apagadas con pmset displaysleepnow."
    }

    func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
            statusMessage = "Abriendo ajustes de Displays."
        }
    }

    private func snapshot(for id: CGDirectDisplayID, displayplacerRecords: [DisplayplacerDisplayRecord]) -> DisplaySnapshot {
        let current = CGDisplayCopyDisplayMode(id)
        let bounds = CGDisplayBounds(id)
        let coreGraphicsModes = displayModes(for: id)
        let stored = UserDefaults.standard.object(forKey: brightnessKey(id)) as? Double
        let width = current?.width ?? Int(bounds.width)
        let height = current?.height ?? Int(bounds.height)
        let refreshRate = current?.refreshRate ?? 0
        let matchedRecord = matchDisplayplacerRecord(
            width: width,
            height: height,
            refreshRate: refreshRate,
            isMain: CGDisplayIsMain(id) != 0,
            records: displayplacerRecords
        )
        return DisplaySnapshot(
            id: id,
            displayplacerID: matchedRecord?.id,
            name: displayName(for: id),
            isBuiltin: CGDisplayIsBuiltin(id) != 0,
            isMain: CGDisplayIsMain(id) != 0,
            isActive: CGDisplayIsActive(id) != 0,
            isOnline: CGDisplayIsOnline(id) != 0,
            width: width,
            height: height,
            pixelWidth: CGDisplayPixelsWide(id),
            pixelHeight: CGDisplayPixelsHigh(id),
            refreshRate: refreshRate,
            modes: mergedModes(coreGraphicsModes: coreGraphicsModes, displayplacerModes: matchedRecord?.modes ?? []),
            softwareBrightness: stored ?? 1.0
        )
    }

    private func displayModes(for id: CGDirectDisplayID) -> [DisplayModeOption] {
        let options = ["kCGDisplayShowDuplicateLowResolution": true] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { return [] }

        var seen = Set<String>()
        let modes: [DisplayModeOption] = rawModes.compactMap { mode -> DisplayModeOption? in
            guard mode.width >= 800, mode.height >= 600 else { return nil }
            let rate = mode.refreshRate
            let key = "\(mode.width)x\(mode.height)@\(Int(rate.rounded()))"
            guard seen.insert(key).inserted else { return nil }
            return DisplayModeOption(
                id: key,
                width: mode.width,
                height: mode.height,
                refreshRate: rate,
                scaling: nil,
                colorDepth: nil,
                mode: mode
            )
        }
        return modes.sorted {
            if $0.width == $1.width {
                if $0.height == $1.height { return $0.refreshRate > $1.refreshRate }
                return $0.height > $1.height
            }
            return $0.width > $1.width
        }
    }

    private func displayName(for id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == id
        }) {
            return screen.localizedName
        }
        if CGDisplayIsBuiltin(id) != 0 { return "Built-in Display" }
        return "Display \(id)"
    }

    private func brightnessKey(_ id: CGDirectDisplayID) -> String {
        "\(brightnessPrefix)\(id)"
    }

    private func updateBrightness(_ value: Double, for displayID: CGDirectDisplayID) {
        displays = displays.map { display in
            guard display.id == displayID else { return display }
            var updated = display
            updated.softwareBrightness = value
            return updated
        }
    }

    private func setDisplayConnectionWithDisplayplacer(_ displayplacerID: String, enabled: Bool) async -> Bool {
        await runDisplayplacerArgument("id:\(displayplacerID) enabled:\(enabled ? "true" : "false")")
    }

    private func runDisplayplacerArgument(_ argument: String) async -> Bool {
        guard let executable = displayplacerExecutable() else { return false }
        let out = try? await runShell(
            executable: executable,
            args: [argument]
        )
        return out != nil
    }

    private func displayplacerExecutable() -> String? {
        ["/opt/homebrew/bin/displayplacer", "/usr/local/bin/displayplacer"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func readDisplayplacerRecords() async -> [DisplayplacerDisplayRecord] {
        guard let executable = displayplacerExecutable(),
              let output = try? await runShell(executable: executable, args: ["list"]) else { return [] }
        return parseDisplayplacerRecords(output)
    }

    private func parseDisplayplacerRecords(_ output: String) -> [DisplayplacerDisplayRecord] {
        let commandArguments = output
            .split(separator: "\n")
            .last(where: { $0.hasPrefix("displayplacer ") })?
            .matches(of: /"([^"]+)"/)
            .map { String($0.1) } ?? []

        return output
            .components(separatedBy: "\n\n")
            .filter { $0.contains("Persistent screen id:") }
            .enumerated()
            .compactMap { index, block -> DisplayplacerDisplayRecord? in
                guard let id = value(after: "Persistent screen id:", in: block),
                      let resolution = value(after: "Resolution:", in: block),
                      let enabledRaw = value(after: "Enabled:", in: block) else { return nil }
                let parts = resolution.split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                let hz = Double(value(after: "Hertz:", in: block) ?? "") ?? 0
                let type = value(after: "Type:", in: block) ?? "Display"
                let isMain = block.contains(" - main display")
                return DisplayplacerDisplayRecord(
                    id: id,
                    name: displayName(fromDisplayplacerType: type),
                    configArgument: commandArguments.first(where: { $0.contains("id:\(id) ") }) ?? "id:\(id) enabled:true",
                    enabled: enabledRaw == "true",
                    width: parts[0],
                    height: parts[1],
                    refreshRate: hz,
                    isMain: isMain,
                    modes: parseDisplayplacerModes(block)
                )
            }
    }

    private func parseDisplayplacerModes(_ block: String) -> [DisplayplacerMode] {
        block.split(separator: "\n").compactMap { rawLine -> DisplayplacerMode? in
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("mode "),
                  line.contains("res:"),
                  !line.contains("Unsafe") else { return nil }
            let modeID = line
                .split(separator: ":")
                .first?
                .replacingOccurrences(of: "mode ", with: "") ?? UUID().uuidString
            guard let resolution = tokenValue("res", in: line) else { return nil }
            let parts = resolution.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return DisplayplacerMode(
                id: "displayplacer-\(modeID)-\(resolution)-\(tokenValue("hz", in: line) ?? "0")-\(line.contains("scaling:on") ? "hidpi" : "native")",
                width: parts[0],
                height: parts[1],
                refreshRate: Double(tokenValue("hz", in: line) ?? "") ?? 0,
                colorDepth: Int(tokenValue("color_depth", in: line) ?? "") ?? 8,
                scaling: line.contains("scaling:on")
            )
        }
    }

    private func tokenValue(_ name: String, in line: String) -> String? {
        line
            .split(separator: " ")
            .first(where: { $0.hasPrefix("\(name):") })?
            .dropFirst(name.count + 1)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergedModes(
        coreGraphicsModes: [DisplayModeOption],
        displayplacerModes: [DisplayplacerMode]
    ) -> [DisplayModeOption] {
        let displayplacerOptions = displayplacerModes.map {
            DisplayModeOption(
                id: $0.id,
                width: $0.width,
                height: $0.height,
                refreshRate: $0.refreshRate,
                scaling: $0.scaling,
                colorDepth: $0.colorDepth,
                mode: nil
            )
        }
        var seen = Set<String>()
        return (displayplacerOptions + coreGraphicsModes)
            .filter { mode in
                let key = "\(mode.width)x\(mode.height)@\(Int(mode.refreshRate.rounded()))-\(mode.scaling == true ? "hidpi" : "native")"
                return seen.insert(key).inserted
            }
            .sorted {
                if $0.width == $1.width {
                    if $0.height == $1.height {
                        if $0.scaling == $1.scaling { return $0.refreshRate > $1.refreshRate }
                        return $0.scaling == true
                    }
                    return $0.height > $1.height
                }
                return $0.width > $1.width
            }
    }

    private func value(after prefix: String, in block: String) -> String? {
        block
            .split(separator: "\n")
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayName(fromDisplayplacerType type: String) -> String {
        if type.contains("built in") { return "Built-in Display" }
        return type.replacingOccurrences(of: " screen", with: "").capitalized
    }

    private func matchDisplayplacerRecord(
        width: Int,
        height: Int,
        refreshRate: Double,
        isMain: Bool,
        records: [DisplayplacerDisplayRecord]
    ) -> DisplayplacerDisplayRecord? {
        records.first {
            $0.enabled &&
            $0.width == width &&
            $0.height == height &&
            abs($0.refreshRate - refreshRate) < 1 &&
            $0.isMain == isMain
        } ?? records.first {
            $0.enabled &&
            $0.width == width &&
            $0.height == height &&
            abs($0.refreshRate - refreshRate) < 1
        } ?? records.first {
            $0.enabled &&
            $0.width == width &&
            $0.height == height
        }
    }

    private func mergeDisconnectedRecords(_ currentRecords: [DisplayplacerDisplayRecord]) {
        let activeIDs = Set(displays.map { "\($0.id)" } + currentRecords.filter(\.enabled).map(\.id))
        disconnectedDisplays = storedDisconnectedRecords().filter { !activeIDs.contains($0.id) }
        storeDisconnectedRecords(disconnectedDisplays)
    }

    private func rememberDisconnected(_ record: DisplayplacerDisplayRecord) {
        var records = storedDisconnectedRecords().filter { $0.id != record.id }
        records.append(record)
        disconnectedDisplays = records
        storeDisconnectedRecords(records)
    }

    private func forgetDisconnected(_ id: String) {
        let records = storedDisconnectedRecords().filter { $0.id != id }
        disconnectedDisplays = records
        storeDisconnectedRecords(records)
    }

    private func storedDisconnectedRecords() -> [DisplayplacerDisplayRecord] {
        guard let data = UserDefaults.standard.data(forKey: disconnectedKey),
              let records = try? JSONDecoder().decode([DisplayplacerDisplayRecord].self, from: data) else { return [] }
        return records
    }

    private func storeDisconnectedRecords(_ records: [DisplayplacerDisplayRecord]) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: disconnectedKey)
        }
    }
}

@MainActor
enum DisplayGammaController {
    private struct GammaTable {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    // Tabla original por display, capturada antes del primer dimming.
    private static var originalTables: [CGDirectDisplayID: GammaTable] = [:]

    static func apply(brightness: Double, to displayID: CGDirectDisplayID) -> Bool {
        guard let original = originalTables[displayID] ?? captureTable(displayID) else { return false }
        if originalTables[displayID] == nil {
            originalTables[displayID] = original
        }

        let factor = CGGammaValue(max(0.0, min(1.0, brightness)))
        let red = original.red.map { $0 * factor }
        let green = original.green.map { $0 * factor }
        let blue = original.blue.map { $0 * factor }

        return CGSetDisplayTransferByTable(displayID, UInt32(red.count), red, green, blue) == .success
    }

    static func restore(_ displayID: CGDirectDisplayID) {
        // Reponer sólo la tabla de ese display; CGDisplayRestoreColorSyncSettings resetearía todos.
        if let original = originalTables.removeValue(forKey: displayID) {
            _ = CGSetDisplayTransferByTable(displayID, UInt32(original.red.count), original.red, original.green, original.blue)
        }
        if originalTables.isEmpty {
            CGDisplayRestoreColorSyncSettings()
        }
    }

    static func restoreAll() {
        originalTables.removeAll()
        CGDisplayRestoreColorSyncSettings()
    }

    private static func captureTable(_ displayID: CGDirectDisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(displayID)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = [CGGammaValue](repeating: 0, count: Int(capacity))
        var blue = [CGGammaValue](repeating: 0, count: Int(capacity))
        var sampleCount: UInt32 = 0
        let result = CGGetDisplayTransferByTable(displayID, capacity, &red, &green, &blue, &sampleCount)
        guard result == .success, sampleCount > 0 else { return nil }
        let count = Int(sampleCount)
        return GammaTable(
            red: Array(red.prefix(count)),
            green: Array(green.prefix(count)),
            blue: Array(blue.prefix(count))
        )
    }
}

@MainActor
final class DisplayDimmingOverlayController {
    static let shared = DisplayDimmingOverlayController()

    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func setBrightness(_ brightness: Double, for displayID: CGDirectDisplayID) {
        let clamped = min(max(brightness, 0.0), 1.0)
        guard clamped < 0.995 else {
            restore(displayID)
            return
        }
        guard let screen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == displayID
        }) else { return }

        let window = windows[displayID] ?? makeWindow(for: screen)
        window.setFrame(screen.frame, display: true)
        window.backgroundColor = NSColor.black.withAlphaComponent(1.0 - clamped)
        window.orderFrontRegardless()
        windows[displayID] = window
    }

    func restore(_ displayID: CGDirectDisplayID) {
        windows[displayID]?.orderOut(nil)
        windows.removeValue(forKey: displayID)
    }

    func restoreAll() {
        windows.values.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }
}

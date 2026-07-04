import SwiftUI
import AppKit

struct SystemView: View {
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var displayState: DisplayControlState
    @EnvironmentObject var menuBarBridge: MenuBarBridge
    @EnvironmentObject var loginItem: LoginItemState
    @StateObject private var powerState = PowerManagementState()

    @State private var snapshot = SystemSnapshot.empty
    @State private var isRefreshing = false
    @State private var showHiddenFiles = false
    @State private var showExtensions = false
    @State private var showPathBar = false
    @State private var showStatusBar = false
    @State private var dockAutohide = false
    @State private var screenshotType = "png"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                healthGrid
                StatsSection()
                DisplayManagementSection(state: displayState)
                PowerManagementSection(state: powerState)
                storageSection
                securitySection
                finderSection
                spotlightSection
                networkSection
                launchAgentsSection
                presetsSection
                LogView()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task {
            loginItem.refresh()
            await refresh()
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                systemHeaderTitle
                Spacer(minLength: 20)
                loginItemHeaderToggle
                headerActions
            }
            VStack(alignment: .leading, spacing: 14) {
                systemHeaderTitle
                HStack(spacing: 10) {
                    loginItemHeaderToggle
                    headerActions
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(Rectangle().frame(width: 4).foregroundColor(Theme.accent), alignment: .leading)
        .cornerRadius(12)
    }

    private var systemHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SISTEMA").font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Theme.accent)
            Text("Mantenimiento seguro de macOS").font(.title2).bold()
            Text("Limpieza medible, seguridad visible, red, Spotlight y tweaks reversibles sin scripts sospechosos.")
                .foregroundColor(Theme.textSecondary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            coffeeToggleButton
            SystemActionButton(title: "Re-verificar", symbol: "arrow.clockwise", color: Theme.blue, busy: isRefreshing) {
                Task { await refresh() }
            }
            .disabled(isRefreshing)
        }
    }

    private var loginItemHeaderToggle: some View {
        Toggle(isOn: loginItemBinding) {
            HStack(spacing: 8) {
                Image(systemName: loginItem.isEnabled ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                    .font(.system(size: 15, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Abrir al iniciar")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(loginItem.statusText)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .foregroundColor(loginItemColor)
        .background(loginItemColor.opacity(0.14))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(loginItemColor.opacity(0.45)))
        .clipShape(.rect(cornerRadius: 8))
        .help("Abrir MT3K Mac Tools automáticamente al iniciar sesión")
        .contextMenu {
            Button("Abrir Login Items") {
                loginItem.openLoginItemsSettings()
            }
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { enabled in
                Task { await loginItem.setEnabled(enabled) }
            }
        )
    }

    private var loginItemColor: Color {
        if loginItem.isEnabled { return Theme.green }
        if loginItem.status == .requiresApproval { return Theme.amber }
        return Theme.textSecondary
    }

    private var coffeeToggleButton: some View {
        Button {
            Task {
                await powerState.toggleAggressiveCaffeine()
                menuBarBridge.refreshCaffeineStatus()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: powerState.isMT3KActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 15, weight: .bold))
                Text(powerState.isMT3KActive ? "Caffeine ON" : "Caffeine")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: 132, minHeight: 34)
            .padding(.horizontal, 10)
            .foregroundColor(powerState.isMT3KActive ? Theme.amber : Theme.textSecondary)
            .background((powerState.isMT3KActive ? Theme.amber : Theme.textSecondary).opacity(powerState.isMT3KActive ? 0.14 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((powerState.isMT3KActive ? Theme.amber : Theme.border).opacity(0.45)))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(powerState.isMT3KActive ? "Detener caffeinate de MT3K y volver al estado normal" : "Activar Caffeine agresivo (-dimsu)")
    }

    private var healthGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
            SystemHealthTile(title: "macOS", detail: snapshot.macOS, ok: true, symbol: "desktopcomputer")
            SystemHealthTile(title: "Hardware", detail: snapshot.hardware, ok: true, symbol: "cpu.fill")
            SystemHealthTile(title: "Uptime", detail: snapshot.uptime, ok: true, symbol: "clock.fill")
            SystemHealthTile(title: "Disco libre", detail: snapshot.diskFree, ok: snapshot.diskLooksOK, symbol: "internaldrive.fill")
            SystemHealthTile(title: "Batería", detail: snapshot.battery, ok: snapshot.batteryLooksOK, symbol: "battery.75percent")
            SystemHealthTile(title: "FileVault", detail: snapshot.fileVault, ok: snapshot.fileVault.contains("On"), symbol: "lock.shield.fill")
            SystemHealthTile(title: "Firewall", detail: snapshot.firewall, ok: snapshot.firewall.contains("On"), symbol: "flame.fill")
            SystemHealthTile(title: "Gatekeeper", detail: snapshot.gatekeeper, ok: snapshot.gatekeeper.contains("enabled"), symbol: "checkmark.shield.fill")
            SystemHealthTile(title: "SIP", detail: snapshot.sip, ok: snapshot.sip.contains("enabled"), symbol: "shield.lefthalf.filled")
            SystemHealthTile(title: "LaunchAgents", detail: snapshot.launchAgentsSummary, ok: true, symbol: "list.bullet.rectangle.fill")
        }
    }

    private var storageSection: some View {
        SystemPanel(title: "Storage Cleaner seguro", symbol: "externaldrive.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                StorageTile(title: "Caches usuario", value: snapshot.userCachesSize)
                StorageTile(title: "Logs usuario", value: snapshot.userLogsSize)
                StorageTile(title: "Xcode DerivedData", value: snapshot.derivedDataSize)
                StorageTile(title: "Homebrew cache", value: snapshot.brewCacheSize)
                StorageTile(title: "Trash", value: snapshot.trashSize)
            }
            actionRow {
                SystemActionButton(title: "Limpiar caches", symbol: "sparkles", color: Theme.green) {
                    Task { await runAndRefresh("Limpiando caches de usuario...", "rm -rf \"$HOME/Library/Caches\"/*") }
                }
                SystemActionButton(title: "Limpiar Brew", symbol: "shippingbox.fill", color: Theme.green) {
                    Task { await runAndRefresh("Limpiando cache de Homebrew...", "brew cleanup -s && rm -rf \"$(brew --cache)\"/*") }
                }
                SystemActionButton(title: "Limpiar DerivedData", symbol: "hammer.fill", color: Theme.amber) {
                    Task { await runAndRefresh("Limpiando Xcode DerivedData...", "rm -rf \"$HOME/Library/Developer/Xcode/DerivedData\"/*") }
                }
                SystemActionButton(title: "Vaciar Trash", symbol: "trash.fill", color: Theme.accent) {
                    Task { await runAndRefresh("Vaciando Trash del usuario...", "rm -rf \"$HOME/.Trash\"/*") }
                }
            }
        }
    }

    private var securitySection: some View {
        SystemPanel(title: "Privacy y Seguridad", symbol: "lock.shield.fill") {
            SystemInfoRow(label: "FileVault", value: snapshot.fileVault)
            SystemInfoRow(label: "Firewall", value: snapshot.firewall)
            SystemInfoRow(label: "Gatekeeper", value: snapshot.gatekeeper)
            SystemInfoRow(label: "SIP", value: snapshot.sip)
            Text("El app no desactiva protecciones. Para seguridad, solo abre ajustes, verifica estado o restaura defaults seguros.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            actionRow {
                SystemActionButton(title: "Abrir FileVault", symbol: "lock.fill", color: Theme.blue) {
                    openSettings("com.apple.settings.PrivacySecurity.extension")
                }
                SystemActionButton(title: "Abrir Firewall", symbol: "flame.fill", color: Theme.blue) {
                    openSettings("com.apple.Network-Settings.extension")
                }
                SystemActionButton(title: "Restaurar Gatekeeper", symbol: "checkmark.shield.fill", color: Theme.green) {
                    openTerminalCommand("sudo spctl --master-enable && spctl --status", title: "Restore Gatekeeper")
                }
            }
        }
    }

    private var finderSection: some View {
        SystemPanel(title: "Finder, Dock y Screenshots", symbol: "macwindow") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                Toggle("Mostrar archivos ocultos", isOn: Binding(
                    get: { showHiddenFiles },
                    set: { value in showHiddenFiles = value; applyFinderBool("AppleShowAllFiles", value: value) }
                ))
                Toggle("Mostrar extensiones", isOn: Binding(
                    get: { showExtensions },
                    set: { value in showExtensions = value; applyFinderBool("AppleShowAllExtensions", value: value) }
                ))
                Toggle("Path bar", isOn: Binding(
                    get: { showPathBar },
                    set: { value in showPathBar = value; applyFinderBool("ShowPathbar", value: value) }
                ))
                Toggle("Status bar", isOn: Binding(
                    get: { showStatusBar },
                    set: { value in showStatusBar = value; applyFinderBool("ShowStatusBar", value: value) }
                ))
                Toggle("Dock autohide", isOn: Binding(
                    get: { dockAutohide },
                    set: { value in dockAutohide = value; applyDockAutohide(value) }
                ))
            }
            HStack(spacing: 10) {
                Picker("Screenshots", selection: $screenshotType) {
                    Text("PNG").tag("png")
                    Text("JPG").tag("jpg")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                SystemActionButton(title: "Aplicar formato", symbol: "camera.viewfinder", color: Theme.blue) {
                    Task { await runAndRefresh("Cambiando formato de screenshots...", "defaults write com.apple.screencapture type \(screenshotType.shellQuoted); killall SystemUIServer") }
                }
                SystemActionButton(title: "Restaurar visual", symbol: "arrow.uturn.backward.circle.fill", color: Theme.amber) {
                    Task { await restoreVisualDefaults() }
                }
            }
        }
    }

    private var spotlightSection: some View {
        SystemPanel(title: "Spotlight", symbol: "magnifyingglass.circle.fill") {
            SystemInfoRow(label: "Estado", value: snapshot.spotlightStatus)
            actionRow {
                SystemActionButton(title: "Reindexar", symbol: "arrow.triangle.2.circlepath", color: Theme.amber) {
                    openTerminalCommand("sudo mdutil -E /", title: "Reindex Spotlight")
                }
                SystemActionButton(title: "Estado completo", symbol: "doc.text.magnifyingglass", color: Theme.blue) {
                    Task { await runAndRefresh("Estado de Spotlight...", "mdutil -s /") }
                }
                SystemActionButton(title: "Abrir ajustes", symbol: "gearshape.fill", color: Theme.blue) {
                    openSettings("com.apple.Spotlight-Settings.extension")
                }
            }
        }
    }

    private var networkSection: some View {
        SystemPanel(title: "Network Tools", symbol: "network") {
            SystemInfoRow(label: "IP local", value: snapshot.localIP)
            SystemInfoRow(label: "DNS", value: snapshot.dnsServers)
            SystemInfoRow(label: "Gateway", value: snapshot.router)
            actionRow {
                SystemActionButton(title: "Flush DNS", symbol: "eraser.fill", color: Theme.amber) {
                    openTerminalCommand("sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder", title: "Flush DNS")
                }
                SystemActionButton(title: "Ping test", symbol: "dot.radiowaves.left.and.right", color: Theme.green) {
                    Task { await runAndRefresh("Ping 1.1.1.1...", "ping -c 4 1.1.1.1") }
                }
                SystemActionButton(title: "IP pública", symbol: "globe.americas.fill", color: Theme.blue) {
                    Task { await runAndRefresh("Consultando IP pública...", "curl -fsS https://ifconfig.me || curl -fsS https://api.ipify.org") }
                }
                SystemActionButton(title: "Abrir Network", symbol: "gearshape.fill", color: Theme.blue) {
                    openSettings("com.apple.Network-Settings.extension")
                }
            }
        }
    }

    private var launchAgentsSection: some View {
        SystemPanel(title: "Login Items y Launch Agents", symbol: "list.bullet.rectangle.fill") {
            SystemInfoRow(label: "Usuario", value: "\(snapshot.userLaunchAgentsCount) en ~/Library/LaunchAgents")
            SystemInfoRow(label: "Sistema", value: "\(snapshot.systemLaunchAgentsCount) agents, \(snapshot.systemLaunchDaemonsCount) daemons")
            Text("Aquí no borramos nada automáticamente. Los launch agents pueden pertenecer a apps legítimas; primero inspecciona.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
            actionRow {
                SystemActionButton(title: "Abrir user agents", symbol: "folder.fill", color: Theme.blue) {
                    openFolder("~/Library/LaunchAgents")
                }
                SystemActionButton(title: "Abrir system agents", symbol: "folder.fill", color: Theme.blue) {
                    openFolder("/Library/LaunchAgents")
                }
                SystemActionButton(title: "Abrir daemons", symbol: "folder.fill", color: Theme.blue) {
                    openFolder("/Library/LaunchDaemons")
                }
                SystemActionButton(title: "Listar recientes", symbol: "list.bullet", color: Theme.green) {
                    Task { await runAndRefresh("LaunchAgents recientes...", "ls -lt \"$HOME/Library/LaunchAgents\" /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null | head -80") }
                }
            }
        }
    }

    private var presetsSection: some View {
        SystemPanel(title: "Maintenance Presets", symbol: "wand.and.stars") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                PresetButton(title: "Limpieza segura", detail: "Caches usuario, Brew cache, logs y Trash.", symbol: "sparkles", color: Theme.green) {
                    Task { await safeCleanupPreset() }
                }
                PresetButton(title: "Reparar red", detail: "Flush DNS, ping test y refresco de estado.", symbol: "network", color: Theme.blue) {
                    openTerminalCommand("sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; ping -c 4 1.1.1.1", title: "Repair Network")
                }
                PresetButton(title: "Reset visual", detail: "Finder/Dock/screenshot defaults sanos.", symbol: "macwindow", color: Theme.amber) {
                    Task { await restoreVisualDefaults() }
                }
                PresetButton(title: "Performance Mac", detail: "Reduce animaciones y activa Dock autohide.", symbol: "bolt.fill", color: Theme.accent) {
                    Task { await performancePreset() }
                }
            }
        }
    }

    private func actionRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        // LazyVGrid wraps action buttons across as many columns as fit, instead of
        // ViewThatFits collapsing the whole row into one tall single column.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            content()
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        snapshot = await SystemSnapshot.capture()
        await powerState.refresh()
        showHiddenFiles = snapshot.showHiddenFiles
        showExtensions = snapshot.showExtensions
        showPathBar = snapshot.showPathBar
        showStatusBar = snapshot.showStatusBar
        dockAutohide = snapshot.dockAutohide
        screenshotType = snapshot.screenshotType.isEmpty ? "png" : snapshot.screenshotType
    }

    private func applyFinderBool(_ key: String, value: Bool) {
        Task {
            await runAndRefresh("Aplicando Finder \(key)...", "defaults write com.apple.finder \(key) -bool \(value ? "true" : "false"); killall Finder")
        }
    }

    private func applyDockAutohide(_ value: Bool) {
        Task {
            await runAndRefresh("Aplicando Dock autohide...", "defaults write com.apple.dock autohide -bool \(value ? "true" : "false"); killall Dock")
        }
    }

    private func restoreVisualDefaults() async {
        await runAndRefresh("Restaurando defaults visuales...", """
        defaults write com.apple.finder AppleShowAllFiles -bool false
        defaults write NSGlobalDomain AppleShowAllExtensions -bool true
        defaults write com.apple.finder ShowPathbar -bool true
        defaults write com.apple.finder ShowStatusBar -bool true
        defaults write com.apple.dock autohide -bool false
        defaults write com.apple.dock expose-animation-duration -float 0.1
        defaults write com.apple.screencapture type png
        killall Finder
        killall Dock
        killall SystemUIServer
        """)
    }

    private func safeCleanupPreset() async {
        await runAndRefresh("Ejecutando limpieza segura...", """
        rm -rf "$HOME/Library/Caches"/*
        rm -rf "$HOME/Library/Logs"/*
        rm -rf "$HOME/.Trash"/*
        rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*
        brew cleanup -s 2>/dev/null || true
        """)
    }

    private func performancePreset() async {
        await runAndRefresh("Aplicando preset de performance visual...", """
        defaults write com.apple.dock autohide -bool true
        defaults write com.apple.dock autohide-delay -float 0
        defaults write com.apple.dock autohide-time-modifier -float 0.25
        defaults write com.apple.dock expose-animation-duration -float 0.1
        defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
        killall Dock
        """)
    }

    private func runAndRefresh(_ startMessage: String, _ command: String) async {
        log.append(startMessage, level: .info)
        do {
            let output = try await runShell(executable: "/bin/zsh", args: ["-lc", command])
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { log.append(trimmed, level: .success) }
            await refresh()
        } catch {
            log.append(error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines), level: .error)
            await refresh()
        }
    }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFolder(_ path: String) {
        let resolved = NSString(string: path).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: resolved))
    }

    private func openTerminalCommand(_ command: String, title: String) {
        do {
            let script = """
            #!/bin/zsh
            set -e
            \(command)
            echo
            echo "Listo. Puedes cerrar esta ventana."
            read -k 1 "?Presiona cualquier tecla para cerrar..."
            """
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("mt3k-\(title.replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString).command")
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try openInTerminal(scriptPath: url.path)
            log.append("Abriendo Terminal: \(title)", level: .info)
        } catch {
            log.append("No se pudo abrir Terminal: \(error.localizedDescription)", level: .error)
        }
    }
}

private struct SystemSnapshot {
    var macOS: String
    var hardware: String
    var uptime: String
    var diskFree: String
    var diskLooksOK: Bool
    var battery: String
    var batteryLooksOK: Bool
    var fileVault: String
    var firewall: String
    var gatekeeper: String
    var sip: String
    var autoUpdate: Bool
    var userCachesSize: String
    var userLogsSize: String
    var derivedDataSize: String
    var brewCacheSize: String
    var trashSize: String
    var spotlightStatus: String
    var localIP: String
    var dnsServers: String
    var router: String
    var userLaunchAgentsCount: Int
    var systemLaunchAgentsCount: Int
    var systemLaunchDaemonsCount: Int
    var launchAgentsSummary: String
    var loginItems: String
    var showHiddenFiles: Bool
    var showExtensions: Bool
    var showPathBar: Bool
    var showStatusBar: Bool
    var dockAutohide: Bool
    var screenshotType: String

    static let empty = SystemSnapshot(
        macOS: "", hardware: "", uptime: "", diskFree: "", diskLooksOK: true,
        battery: "", batteryLooksOK: true, fileVault: "", firewall: "", gatekeeper: "",
        sip: "", autoUpdate: false, userCachesSize: "-", userLogsSize: "-", derivedDataSize: "-",
        brewCacheSize: "-", trashSize: "-", spotlightStatus: "", localIP: "",
        dnsServers: "", router: "", userLaunchAgentsCount: 0, systemLaunchAgentsCount: 0,
        systemLaunchDaemonsCount: 0, launchAgentsSummary: "", loginItems: "—",
        showHiddenFiles: false, showExtensions: false, showPathBar: false, showStatusBar: false,
        dockAutohide: false, screenshotType: "png"
    )

    static func capture() async -> SystemSnapshot {
        async let macOS = checked("sw_vers -productName; sw_vers -productVersion; sw_vers -buildVersion")
        async let hardware = checked("sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m")
        async let mem = checked("sysctl -n hw.memsize | awk '{printf \"%.0f GB\", $1/1024/1024/1024}'")
        async let uptime = checked("uptime | sed 's/^.*up //; s/, [0-9]* users.*//; s/, load averages.*//'")
        async let disk = checked("target='/System/Volumes/Data'; [ -d \"$target\" ] || target='/'; df -H \"$target\" | awk 'NR==2 {print $4 \" libres de \" $2 \" (\" $5 \" usado)\"}'")
        async let diskPercent = checked("target='/System/Volumes/Data'; [ -d \"$target\" ] || target='/'; df \"$target\" | awk 'NR==2 {gsub(\"%\", \"\", $5); print $5}'")
        async let battery = checked("""
        cycles=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Cycle Count/ {print $2; exit}')
        condition=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Condition/ {print $2; exit}')
        if [ -n "$cycles" ]; then echo "${condition:-Unknown}, ${cycles} ciclos"; else echo "No aplica"; fi
        """)
        async let fileVault = checked("fdesetup status 2>/dev/null | sed 's/FileVault is //'")
        async let firewall = checked("/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | sed 's/Firewall is //'")
        async let gatekeeper = checked("spctl --status 2>/dev/null")
        async let sip = checked("csrutil status 2>/dev/null | sed 's/System Integrity Protection status: //'")
        async let userCaches = size("$HOME/Library/Caches")
        async let userLogs = size("$HOME/Library/Logs")
        async let derived = size("$HOME/Library/Developer/Xcode/DerivedData")
        async let brewCache = checked("if command -v brew >/dev/null; then du -sh \"$(brew --cache)\" 2>/dev/null | awk '{print $1}'; else echo '-'; fi")
        async let trash = size("$HOME/.Trash")
        async let spotlight = checked("mdutil -s / 2>/dev/null | tail -1 | sed 's/^ *//'")
        async let ip = checked("ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 'No detectada'")
        async let dns = checked("scutil --dns | awk '/nameserver\\[[0-9]+\\]/ {print $3}' | sort -u | tr '\\n' ', ' | sed 's/, $//'")
        async let router = checked("route -n get default 2>/dev/null | awk '/gateway/ {print $2; exit}'")
        async let userAgents = checked("find \"$HOME/Library/LaunchAgents\" -maxdepth 1 -name '*.plist' 2>/dev/null | wc -l | tr -d ' '")
        async let sysAgents = checked("find /Library/LaunchAgents -maxdepth 1 -name '*.plist' 2>/dev/null | wc -l | tr -d ' '")
        async let daemons = checked("find /Library/LaunchDaemons -maxdepth 1 -name '*.plist' 2>/dev/null | wc -l | tr -d ' '")
        async let hidden = checked("defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo false")
        async let ext = checked("defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || echo false")
        async let pathBar = checked("defaults read com.apple.finder ShowPathbar 2>/dev/null || echo false")
        async let statusBar = checked("defaults read com.apple.finder ShowStatusBar 2>/dev/null || echo false")
        async let dockHide = checked("defaults read com.apple.dock autohide 2>/dev/null || echo false")
        async let ssType = checked("defaults read com.apple.screencapture type 2>/dev/null || echo png")
        async let autoDownload = checked("defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || echo 0")
        async let loginItemsRaw = checked("osascript -e 'tell application \"System Events\" to get the name of every login item' 2>/dev/null || echo ''")

        let osLines = await macOS.split(whereSeparator: \.isNewline).map(String.init)
        let os = osLines.count >= 2 ? "\(osLines[0]) \(osLines[1])" : await macOS
        let hw = await hardware
        let memory = await mem
        let diskUsed = Int(await diskPercent) ?? 0
        let batteryText = await battery
        let batteryOK = !batteryText.lowercased().contains("service")
        let ua = Int(await userAgents) ?? 0
        let sa = Int(await sysAgents) ?? 0
        let sd = Int(await daemons) ?? 0
        let loginRaw = await loginItemsRaw
        let loginItemsValue: String = {
            let t = loginRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "—" : t
        }()

        return SystemSnapshot(
            macOS: os,
            hardware: memory.isEmpty ? hw : "\(hw), \(memory)",
            uptime: await uptime,
            diskFree: await disk,
            diskLooksOK: diskUsed < 85,
            battery: batteryText,
            batteryLooksOK: batteryOK,
            fileVault: await fileVault,
            firewall: await firewall,
            gatekeeper: await gatekeeper,
            sip: await sip,
            autoUpdate: (Int(await autoDownload) ?? 0) > 0,
            userCachesSize: await userCaches,
            userLogsSize: await userLogs,
            derivedDataSize: await derived,
            brewCacheSize: await brewCache,
            trashSize: await trash,
            spotlightStatus: await spotlight,
            localIP: await ip,
            dnsServers: await dns,
            router: await router,
            userLaunchAgentsCount: ua,
            systemLaunchAgentsCount: sa,
            systemLaunchDaemonsCount: sd,
            launchAgentsSummary: "\(ua + sa + sd) items",
            loginItems: loginItemsValue,
            showHiddenFiles: bool(await hidden),
            showExtensions: bool(await ext),
            showPathBar: bool(await pathBar),
            showStatusBar: bool(await statusBar),
            dockAutohide: bool(await dockHide),
            screenshotType: await ssType
        )
    }

    private static func checked(_ command: String) async -> String {
        (try? await runShell(executable: "/bin/zsh", args: ["-lc", "\(command) || true"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func size(_ path: String) async -> String {
        await checked("[ -e \(path) ] && du -sh \(path) 2>/dev/null | awk '{print $1}' || echo '-'")
    }

    private static func bool(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return v == "1" || v == "true" || v == "yes"
    }
}

private struct SystemHealthTile: View {
    let title: String
    let detail: String
    let ok: Bool
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(ok ? Theme.green : Theme.amber)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail.isEmpty ? "No detectado" : detail)
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: symbol)
                .foregroundColor(ok ? Theme.green : Theme.blue)
        }
        .padding(12)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct SystemPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundColor(Theme.blue)
                Text(title).font(.headline)
            }
            content
        }
        .padding(18)
        .background(Theme.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 12))
    }
}

private struct SystemInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 110, alignment: .leading)
            Text(value.isEmpty ? "No detectado" : value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct StorageTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.isEmpty ? "-" : value)
                .font(.title3)
                .bold()
            Text(title)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.bgDark.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct SystemActionButton: View {
    let title: String
    let symbol: String
    let color: Color
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(minWidth: 132, minHeight: 34)
            .padding(.horizontal, 10)
            .foregroundColor(color)
            .background(color.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.35)))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct PresetButton: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundColor(color)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).bold()
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(12)
            .background(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.32)))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// `shellQuoted` lives in ScriptRunner.swift as a module-internal extension.

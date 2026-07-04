import Foundation
import SwiftUI

@MainActor
final class InstallCoordinator: ObservableObject {
    enum Status: Equatable {
        case idle
        case queued
        case running(phase: String, line: String)
        case terminal(String)
        case success(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .queued, .running, .terminal: return true
            default: return false
            }
        }

        var succeeded: Bool {
            if case .success = self { return true }
            return false
        }
    }

    @Published private(set) var statuses: [String: Status] = [:]
    @Published private(set) var queue: [CatalogItem] = []
    @Published private(set) var isRunningQueue = false

    func status(for item: CatalogItem) -> Status {
        statuses[item.id] ?? .idle
    }

    func install(_ item: CatalogItem, force: Bool = false, log: LogStore) async {
        guard !status(for: item).isBusy else { return }
        await runInstall(item, force: force, log: log)
    }

    func update(_ item: CatalogItem, log: LogStore) async {
        guard !status(for: item).isBusy else { return }
        await runUpgrade(item, log: log)
    }

    func installQueue(_ items: [CatalogItem], log: LogStore) async {
        guard !isRunningQueue else { return }
        let uniqueItems = unique(items)
        guard !uniqueItems.isEmpty else { return }

        isRunningQueue = true
        queue = uniqueItems
        for item in uniqueItems {
            statuses[item.id] = .queued
        }
        log.append("Cola iniciada: \(uniqueItems.count) items.", level: .info)

        for item in uniqueItems {
            let behavior = UserDefaults.standard.string(forKey: "installBehavior") ?? "ask"
            var shouldAdoptIntoBrew = false
            if appExists(item), item.install.brewPackageName != nil {
                shouldAdoptIntoBrew = await !isKnownBrewInstalled(item)
            }
            if appExists(item), behavior != "force", !shouldAdoptIntoBrew {
                statuses[item.id] = .success("Ya existe en /Applications; omitido en cola")
                log.append("\(item.name) ya existe; omitido en cola.", level: .info)
                continue
            }
            if shouldAdoptIntoBrew {
                log.append("\(item.name) existe en /Applications; instalando con --force para gestionarlo vía Brew.", level: .info)
            }
            await runInstall(item, force: behavior == "force" || shouldAdoptIntoBrew, log: log)
        }

        queue.removeAll()
        isRunningQueue = false
        log.append("Cola finalizada.", level: .success)
    }

    private func unique(_ items: [CatalogItem]) -> [CatalogItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func appExists(_ item: CatalogItem) -> Bool {
        guard let appName = item.appName else { return false }
        return FileManager.default.fileExists(atPath: "/Applications/\(appName)")
    }

    private func isKnownBrewInstalled(_ item: CatalogItem) async -> Bool {
        guard let package = item.install.brewPackageName else { return false }
        let shortName = package.components(separatedBy: "/").last ?? package
        var names = [shortName]
        if package != shortName { names.append(package) }
        for name in names {
            if await shellSucceeds("brew list --formula --quiet | grep -Fxq \(shellQuote(name))") { return true }
            if await shellSucceeds("brew list --cask --quiet | grep -Fxq \(shellQuote(name))") { return true }
        }
        return false
    }

    // waitUntilExit bloquea el hilo; nunca ejecutarlo en el MainActor (hitch de UI en la cola).
    private func shellSucceeds(_ command: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", command]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func runInstall(_ item: CatalogItem, force: Bool, log: LogStore) async {
        statuses[item.id] = .running(phase: force ? "Reemplazando" : "Instalando", line: "")
        let prefix = force ? "Reemplazando \(item.name)..." : "Instalando \(item.name)..."

        if case .brewCask(let caskName) = item.install, item.requiresAdminInstall {
            await installViaTerminal(item, caskName: caskName, force: force, log: log)
            return
        }

        log.append(prefix, level: .info)
        var allLines: [String] = []
        do {
            let scriptURL = try resolveScript("install_package.sh")
            var args = item.install.scriptArgs
            if force, case .brewCask = item.install, args.count >= 2 {
                args.insert("--force", at: 1)
            }

            let stream = runShellStream(executable: "/bin/zsh", args: [scriptURL.path] + args)
            var lastMeaningful = ""
            var phase = ""
            for try await line in stream {
                allLines.append(line.text)
                if let nextPhase = detectPhase(line.text) {
                    phase = nextPhase
                }
                statuses[item.id] = .running(phase: phase, line: line.text)

                let lower = line.text.lowercased()
                let isErrorLine = lower.hasPrefix("error:") || lower.contains("error:")
                let isWarn = lower.hasPrefix("warning:")
                if line.text.hasPrefix("==>") ||
                    line.text.hasPrefix("->") ||
                    line.text.hasPrefix("→") ||
                    line.text.contains("✓") ||
                    line.text.contains("successfully installed") ||
                    line.text.hasPrefix("🍺") ||
                    isErrorLine || isWarn {
                    let level: LogStore.Level = isErrorLine ? .error : (isWarn ? .warn : .info)
                    log.append(line.text, level: level)
                }

                if !line.text.contains("%") && !line.text.hasPrefix("#") {
                    lastMeaningful = line.text
                }
            }

            let message = lastMeaningful.isEmpty ? "Instalado correctamente" : lastMeaningful
            statuses[item.id] = .success(message)
            log.append("\(item.name) instalado.", level: .success)
        } catch {
            let errorLines = allLines.filter { $0.lowercased().contains("error:") }
            let detail: String
            if !errorLines.isEmpty {
                detail = errorLines.suffix(2).joined(separator: " · ")
            } else if !allLines.isEmpty {
                detail = allLines.suffix(3).joined(separator: " · ")
            } else {
                detail = error.localizedDescription
            }
            let trimmed = String(detail.prefix(180))
            statuses[item.id] = .failed(trimmed)
            log.append("Error instalando \(item.name): \(detail.prefix(200))", level: .error)
        }
    }

    private func runUpgrade(_ item: CatalogItem, log: LogStore) async {
        guard let args = item.install.upgradeScriptArgs else {
            statuses[item.id] = .failed("Updates automáticos no disponibles para este método")
            return
        }

        statuses[item.id] = .running(phase: "Actualizando", line: "")
        if case .brewCask(let caskName) = item.install, item.requiresAdminInstall {
            await installViaTerminal(item, caskName: caskName, force: false, log: log, command: "upgrade")
            return
        }

        log.append("Actualizando \(item.name)...", level: .info)
        var allLines: [String] = []
        do {
            let scriptURL = try resolveScript("install_package.sh")
            let stream = runShellStream(executable: "/bin/zsh", args: [scriptURL.path] + args)
            var lastMeaningful = ""
            var phase = "Actualizando"
            for try await line in stream {
                allLines.append(line.text)
                if let nextPhase = detectPhase(line.text) {
                    phase = nextPhase
                }
                statuses[item.id] = .running(phase: phase, line: line.text)

                let lower = line.text.lowercased()
                let isErrorLine = lower.hasPrefix("error:") || lower.contains("error:")
                let isWarn = lower.hasPrefix("warning:")
                if line.text.hasPrefix("==>") ||
                    line.text.hasPrefix("->") ||
                    line.text.hasPrefix("→") ||
                    line.text.contains("✓") ||
                    line.text.hasPrefix("🍺") ||
                    isErrorLine || isWarn {
                    let level: LogStore.Level = isErrorLine ? .error : (isWarn ? .warn : .info)
                    log.append(line.text, level: level)
                }
                if !line.text.contains("%") && !line.text.hasPrefix("#") {
                    lastMeaningful = line.text
                }
            }

            let message = lastMeaningful.isEmpty ? "Actualizado correctamente" : lastMeaningful
            statuses[item.id] = .success(message)
            log.append("\(item.name) actualizado.", level: .success)
        } catch {
            let errorLines = allLines.filter { $0.lowercased().contains("error:") }
            let detail: String
            if !errorLines.isEmpty {
                detail = errorLines.suffix(2).joined(separator: " · ")
            } else if !allLines.isEmpty {
                detail = allLines.suffix(3).joined(separator: " · ")
            } else {
                detail = error.localizedDescription
            }
            let trimmed = String(detail.prefix(180))
            statuses[item.id] = .failed(trimmed)
            log.append("Error actualizando \(item.name): \(detail.prefix(200))", level: .error)
        }
    }

    private func installViaTerminal(_ item: CatalogItem, caskName: String, force: Bool, log: LogStore, command: String = "install") async {
        let terminalName = UserDefaults.standard.string(forKey: "preferredTerminal") ?? "Terminal"
        let timeoutMinutes = UserDefaults.standard.double(forKey: "terminalTimeoutMinutes")
        let pollCount = max(1, Int(((timeoutMinutes > 0 ? timeoutMinutes : 6) * 60) / 2))

        log.append("\(item.name): abriendo \(terminalName) para completar \(command)...", level: .info)
        statuses[item.id] = .terminal("Completá el \(command) en Terminal")

        let brew = "/opt/homebrew/bin/brew"
        let forceFlag = force ? "--force " : ""
        let brewAction = command == "upgrade" ? "upgrade" : "install"
        let body = """
        #!/bin/zsh
        printf "\\033[1;35m"
        echo "════════════════════════════════════════════════════════"
        echo " MT3K Mac Tools — Instalando \(item.name)"
        echo "════════════════════════════════════════════════════════"
        printf "\\033[0m"
        echo "Este cask incluye un .pkg de sistema. macOS te va a pedir"
        echo "tu contraseña de admin durante el install."
        echo ""
        \(brew) \(brewAction) --cask \(forceFlag)\(caskName)
        ec=$?
        echo ""
        if [ $ec -eq 0 ]; then
          printf "\\033[1;32m✓ \(item.name) instalado correctamente.\\033[0m\\n"
        else
          printf "\\033[1;31m✗ Install falló con exit $ec.\\033[0m\\n"
        fi
        echo ""
        echo "Podés cerrar esta ventana de Terminal."
        """

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mt3k-\(item.id)-\(UUID().uuidString).command")
        do {
            try body.write(to: tmp, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", terminalName, tmp.path]
            try process.run()
        } catch {
            let message = "No se pudo abrir \(terminalName): \(error.localizedDescription)"
            statuses[item.id] = .failed(message)
            log.append("Error abriendo \(terminalName): \(error.localizedDescription)", level: .error)
            return
        }

        guard let appName = item.appName else {
            statuses[item.id] = .terminal("Continuando en Terminal")
            return
        }

        let target = "/Applications/\(appName)"
        let startTime = Date()
        let initialMTime = (try? FileManager.default.attributesOfItem(atPath: target)[.modificationDate]) as? Date

        for _ in 0..<pollCount {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let exists = FileManager.default.fileExists(atPath: target)
            let mtime = (try? FileManager.default.attributesOfItem(atPath: target)[.modificationDate]) as? Date
            if exists {
                let isNew = initialMTime == nil
                let isReplaced = initialMTime != nil && mtime != nil && mtime! > initialMTime! && Date().timeIntervalSince(startTime) > 5
                if isNew || isReplaced {
                    statuses[item.id] = .success("\(appName) instalado en /Applications")
                    log.append("\(item.name) instalado.", level: .success)
                    return
                }
            }
        }

        statuses[item.id] = .terminal("Terminal sigue abierto — verificá ahí")
    }

    private func detectPhase(_ line: String) -> String? {
        let lower = line.lowercased()
        if lower.contains("downloading") { return "Descargando" }
        if lower.contains("verifying") { return "Verificando" }
        if lower.contains("installing") { return "Instalando" }
        if lower.contains("linking") { return "Vinculando" }
        if lower.contains("moving") { return "Moviendo" }
        if lower.contains("caveats") { return "Notas" }
        if lower.contains("fetching") { return "Fetching" }
        if lower.contains("pouring") { return "Pouring" }
        return nil
    }
}

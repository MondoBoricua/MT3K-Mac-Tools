import Foundation
import AppKit

// MARK: - Shell quoting helper (module-internal)

extension String {
    /// POSIX single-quoted form for safe inclusion in zsh command strings.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

func scriptsDir() throws -> URL {
    if let bundleScripts = Bundle.main.url(forResource: "scripts", withExtension: nil) {
        return bundleScripts
    }
    let exe = URL(fileURLWithPath: CommandLine.arguments[0])
    var dir = exe.deletingLastPathComponent()
    for _ in 0..<10 {
        let candidate = dir.appendingPathComponent("scripts")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        dir = dir.deletingLastPathComponent()
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("scripts")
    if FileManager.default.fileExists(atPath: cwd.path) { return cwd }
    throw NSError(domain: "MT3K", code: 1, userInfo: [NSLocalizedDescriptionKey: "Carpeta scripts/ no encontrada"])
}

func resolveScript(_ name: String) throws -> URL {
    let url = try scriptsDir().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw AdminError.scriptNotFound(url.path)
    }
    // Best-effort chmod +x (only needed on first run after copy)
    _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

func runShell(executable: String, args: [String]) async throws -> String {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args

            var env = ProcessInfo.processInfo.environment
            let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = "\(env["PATH"] ?? ""):\(extra)"
            proc.environment = env

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            // CRÍTICO: drenar el pipe CONCURRENTEMENTE con waitUntilExit().
            // El patrón sin reader concurrente (waitUntilExit → readDataToEndOfFile)
            // se DEADLOCK cuando el child escribe > pipe buffer (~16-64 KB en macOS):
            // el child bloquea en write(), nosotros en waitUntilExit, eternamente.
            // Por eso `ps -e` y otros comandos largos devolvían "" silenciosamente.
            final class DataBox: @unchecked Sendable { var bytes = Data() }
            let box = DataBox()
            let readerQueue = DispatchQueue(label: "shell-reader")
            let readerGroup = DispatchGroup()
            readerGroup.enter()
            readerQueue.async {
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }   // EOF cuando el child cierra el pipe
                    box.bytes.append(chunk)
                }
                readerGroup.leave()
            }

            do {
                try proc.run()
                proc.waitUntilExit()
                readerGroup.wait()   // espera a que el reader drene el resto

                let output = String(data: box.bytes, encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    cont.resume(returning: output)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "Shell",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "exit \(proc.terminationStatus)" : output]
                    ))
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

func openInTerminal(scriptPath: String) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = ["-a", "Terminal", scriptPath]
    try proc.run()
}

/// Show a native macOS password prompt as an alert sheet. Returns nil if cancelled.
@MainActor
func promptForAdminPassword(appName: String) -> String? {
    let alert = NSAlert()
    alert.messageText = "Permisos de admin para instalar \(appName)"
    alert.informativeText = "Este cask incluye un .pkg de sistema. macOS necesita tu contraseña para completar la instalación. La contraseña se usa una sola vez en memoria — no se guarda."
    alert.alertStyle = .informational
    alert.icon = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)
    alert.addButton(withTitle: "Continuar")
    alert.addButton(withTitle: "Cancelar")

    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    field.placeholderString = "Tu contraseña de macOS"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field

    let response = alert.runModal()
    return response == .alertFirstButtonReturn ? field.stringValue : nil
}

struct ShellLine: Sendable {
    let text: String
    let isError: Bool
}

/// Stream stdout/stderr of a child process line-by-line. Splits on both \n and \r
/// so brew's progress bars (which use \r to overwrite) surface as live updates.
func runShellStream(executable: String, args: [String], extraEnv: [String: String] = [:]) -> AsyncThrowingStream<ShellLine, Error> {
    AsyncThrowingStream { continuation in
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = "\(env["PATH"] ?? ""):\(extra)"
        // Force brew to print progress without TTY tricks
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        for (k, v) in extraEnv { env[k] = v }
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            emitShellLines(data, isError: false, continuation: continuation)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            emitShellLines(data, isError: true, continuation: continuation)
        }

        proc.terminationHandler = { p in
            if let leftover = try? outPipe.fileHandleForReading.readToEnd() {
                emitShellLines(leftover, isError: false, continuation: continuation)
            }
            if let leftover = try? errPipe.fileHandleForReading.readToEnd() {
                emitShellLines(leftover, isError: true, continuation: continuation)
            }
            if p.terminationStatus == 0 {
                continuation.finish()
            } else {
                continuation.finish(throwing: NSError(
                    domain: "Shell",
                    code: Int(p.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "exit \(p.terminationStatus)"]
                ))
            }
        }

        do {
            try proc.run()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}

private func emitShellLines(_ data: Data, isError: Bool, continuation: AsyncThrowingStream<ShellLine, Error>.Continuation) {
    guard !data.isEmpty, let str = String(data: data, encoding: .utf8) else { return }
    let clean = stripAnsi(str)
    let parts = clean.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" })
    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            continuation.yield(ShellLine(text: trimmed, isError: isError))
        }
    }
}

private func stripAnsi(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    var inEscape = false
    for ch in s {
        if inEscape {
            // ANSI CSI sequences end with a letter (m, K, J, A-D, etc.)
            if ch.isLetter { inEscape = false }
        } else if ch == "\u{001B}" {
            inEscape = true
        } else {
            out.append(ch)
        }
    }
    return out
}

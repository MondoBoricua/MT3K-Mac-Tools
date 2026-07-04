import Foundation
import SwiftUI
import Security
import Darwin

// MARK: - Log Store

@MainActor
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    enum Level: String {
        case info, success, warn, error
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String

        var timeString: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: timestamp)
        }
    }

    func append(_ message: String, level: Level = .info) {
        entries.append(LogEntry(timestamp: Date(), level: level, message: message))
        if entries.count > 300 {
            entries.removeFirst(entries.count - 300)
        }
    }

    func clear() { entries.removeAll() }
}

// MARK: - Brew preflight state

@MainActor
final class BrewState: ObservableObject {
    @Published var brewInstalled: Bool = false
    @Published var brewPath: String = ""
    @Published var nodeInstalled: Bool = false
    @Published var nodePath: String = ""
    @Published var isRefreshing: Bool = false
    @Published var installedPackages: Set<String> = []
    @Published var outdatedPackages: Set<String> = []

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        async let brew = detect("brew")
        async let node = detect("node")
        let (b, n) = await (brew, node)
        brewPath = b
        brewInstalled = !b.isEmpty
        nodePath = n
        nodeInstalled = !n.isEmpty
        installedPackages = brewInstalled ? await detectInstalled(brewPath: b) : []
        outdatedPackages = brewInstalled ? await detectOutdated(brewPath: b) : []
    }

    func isOutdated(_ method: InstallMethod) -> Bool {
        guard let name = method.brewPackageName else { return false }
        return outdatedPackages.contains(name) || outdatedPackages.contains(name.components(separatedBy: "/").last ?? name)
    }

    func isInstalled(_ method: InstallMethod) -> Bool {
        guard let name = method.brewPackageName else { return false }
        return installedPackages.contains(name) || installedPackages.contains(name.components(separatedBy: "/").last ?? name)
    }

    private nonisolated func detect(_ command: String) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let candidates = [
                    "/opt/homebrew/bin/\(command)",
                    "/usr/local/bin/\(command)",
                    "/usr/bin/\(command)"
                ]
                for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
                    cont.resume(returning: p); return
                }
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-l", "-c", "command -v \(command) 2>/dev/null || true"]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(returning: FileManager.default.isExecutableFile(atPath: out) ? out : "")
                } catch {
                    cont.resume(returning: "")
                }
            }
        }
    }

    private nonisolated func detectOutdated(brewPath: String) async -> Set<String> {
        await withCheckedContinuation { (cont: CheckedContinuation<Set<String>, Never>) in
            DispatchQueue.global(qos: .utility).async {
                guard !brewPath.isEmpty else {
                    cont.resume(returning: [])
                    return
                }

                let command = """
                HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "\(brewPath)" outdated --formula --quiet 2>/dev/null || true
                HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "\(brewPath)" outdated --cask --greedy --quiet 2>/dev/null || true
                """
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", command]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let names = output
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    cont.resume(returning: Set(names))
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }

    private nonisolated func detectInstalled(brewPath: String) async -> Set<String> {
        await withCheckedContinuation { (cont: CheckedContinuation<Set<String>, Never>) in
            DispatchQueue.global(qos: .utility).async {
                guard !brewPath.isEmpty else {
                    cont.resume(returning: [])
                    return
                }

                let command = """
                HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "\(brewPath)" list --formula --quiet 2>/dev/null || true
                HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "\(brewPath)" list --cask --quiet 2>/dev/null || true
                """
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                proc.arguments = ["-lc", command]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError = Pipe()
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let names = output
                        .split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    cont.resume(returning: Set(names))
                } catch {
                    cont.resume(returning: [])
                }
            }
        }
    }
}

// MARK: - Admin Authorization (session-long)

enum AdminError: LocalizedError {
    case createFailed(OSStatus)
    case userDenied
    case symbolMissing
    case execFailed(OSStatus)
    case scriptNotFound(String)
    case notAllowed(String)

    var errorDescription: String? {
        switch self {
        case .createFailed(let s): return "AuthorizationCreate falló (\(s))"
        case .userDenied: return "Permisos denegados o cancelado por el usuario"
        case .symbolMissing: return "AuthorizationExecuteWithPrivileges no disponible"
        case .execFailed(let s): return "Ejecución privilegiada falló (\(s))"
        case .scriptNotFound(let p): return "Script no encontrado: \(p)"
        case .notAllowed(let n): return "Script no permitido: \(n)"
        }
    }
}

@MainActor
final class AdminAuth: ObservableObject {
    @Published private(set) var hasSession: Bool = false
    private var authRef: AuthorizationRef?

    func acquire(prompt: String) throws {
        if authRef != nil { return }

        var auth: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &auth)
        guard createStatus == errAuthorizationSuccess, let auth = auth else {
            throw AdminError.createFailed(createStatus)
        }

        let result = "system.privilege.admin".withCString { (cName: UnsafePointer<CChar>) -> OSStatus in
            var item = AuthorizationItem(
                name: cName,
                valueLength: 0,
                value: nil,
                flags: 0
            )
            return withUnsafeMutablePointer(to: &item) { itemPtr -> OSStatus in
                var rights = AuthorizationRights(count: 1, items: itemPtr)
                let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
                return AuthorizationCopyRights(auth, &rights, nil, flags, nil)
            }
        }

        guard result == errAuthorizationSuccess else {
            AuthorizationFree(auth, [.destroyRights])
            throw AdminError.userDenied
        }

        authRef = auth
        hasSession = true
    }

    /// Run a script with admin privileges. Caches auth for ~5 min (macOS default).
    func runPrivileged(scriptPath: String, args: [String] = []) async throws -> String {
        guard let auth = authRef else { throw AdminError.userDenied }

        typealias ExecFn = @convention(c) (
            AuthorizationRef,
            UnsafePointer<CChar>,
            AuthorizationFlags,
            UnsafePointer<UnsafeMutablePointer<CChar>?>,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus

        let RTLD_DEFAULT_PTR = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(RTLD_DEFAULT_PTR, "AuthorizationExecuteWithPrivileges") else {
            throw AdminError.symbolMissing
        }
        let exec = unsafeBitCast(sym, to: ExecFn.self)

        // Allocate C strings for args + null terminator
        let cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { for ptr in cArgs { if let ptr { free(ptr) } } }

        var pipe: UnsafeMutablePointer<FILE>?
        let status: OSStatus = scriptPath.withCString { pathPtr in
            cArgs.withUnsafeBufferPointer { argsBuf in
                exec(auth, pathPtr, [], argsBuf.baseAddress!, &pipe)
            }
        }

        guard status == errAuthorizationSuccess, let outPipe = pipe else {
            throw AdminError.execFailed(status)
        }

        return await Task.detached(priority: .userInitiated) { () -> String in
            var output = ""
            let bufSize = 4096
            let buf = UnsafeMutablePointer<CChar>.allocate(capacity: bufSize)
            defer {
                buf.deallocate()
                fclose(outPipe)
            }
            while true {
                let n = fread(buf, 1, bufSize, outPipe)
                if n == 0 { break }
                let data = Data(bytes: buf, count: n)
                if let s = String(data: data, encoding: .utf8) {
                    output += s
                }
            }
            return output
        }.value
    }

    func release() {
        if let auth = authRef {
            AuthorizationFree(auth, [.destroyRights])
            authRef = nil
            hasSession = false
        }
    }

    // No deinit: macOS reclaims the AuthorizationRef on process exit.
    // Call release() explicitly to invalidate the session early.
}

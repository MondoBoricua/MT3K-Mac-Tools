import BatteryGuardCore
import Foundation
import Darwin
import IOKit
import IOKit.ps
import SMCKit

let helperLabel = "com.mt3k.mac-tools.battery-helper"
let helperSocketPath = "/var/run/\(helperLabel).sock"
let configDirectory = "/Library/Application Support/MT3K Mac Tools"
let configPath = "\(configDirectory)/battery-guard.json"

// Serializes all SMC + config access between the socket command thread and the
// autonomous poll thread. SMCKit.shared holds a single IOKit connection that is
// not safe to use concurrently.
let guardLock = NSLock()

// MARK: - Autonomous guard config (persisted, root-owned)

struct GuardConfig: Codable {
    var enabled: Bool = false
    var limit: Int = 80
    var resume: Int = 75
    // Top-up transient: suspende el límite hasta 100% o desconexión del charger.
    // Persistido para sobrevivir un reboot a mitad de la carga.
    var topUp: Bool = false

    init(enabled: Bool = false, limit: Int = 80, resume: Int = 75, topUp: Bool = false) {
        self.enabled = enabled
        self.limit = limit
        self.resume = resume
        self.topUp = topUp
    }

    // decodeIfPresent: un battery-guard.json anterior (sin topUp) NO debe fallar
    // el decode — eso resetearía enabled/limit a defaults y apagaría el guard.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 80
        resume = try container.decodeIfPresent(Int.self, forKey: .resume) ?? 75
        topUp = try container.decodeIfPresent(Bool.self, forKey: .topUp) ?? false
    }
}

// In-memory copy; loaded from disk at daemon start, mutated only under guardLock.
// nonisolated(unsafe): top-level globals are main-actor-isolated by default, but
// access here is hand-serialized through guardLock across the socket/poll threads.
nonisolated(unsafe) var currentConfig = GuardConfig()

func loadConfigFromDisk() -> GuardConfig {
    guard let data = FileManager.default.contents(atPath: configPath),
          let decoded = try? JSONDecoder().decode(GuardConfig.self, from: data) else {
        return GuardConfig()
    }
    return decoded
}

func persistConfig(_ config: GuardConfig) {
    try? FileManager.default.createDirectory(atPath: configDirectory, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(config) {
        try? data.write(to: URL(fileURLWithPath: configPath))
    }
}

func logDaemon(_ message: String) {
    fputs("[\(helperLabel)] \(message)\n", stderr)
}

// MARK: - Battery reading via IOKit AppleSmartBattery (no app dependency)

// Reads charge % and charger-present from the AppleSmartBattery IORegistry node.
//
// IMPORTANT: `onAC` is derived from `ExternalConnected`, NOT from the IOPS
// power-source state (`kIOPSPowerSourceStateKey`). That IOPS field answers
// "what is the system drawing from right now", which macOS flips to "Battery
// Power" while charging is inhibited at the limit — even though the charger is
// still plugged in. The autonomous loop read that flip as an unplug and lifted
// the inhibit, letting the battery ratchet up past the limit (80% → 99%).
// `ExternalConnected` reflects physical charger presence and stays true while
// inhibited, which is the signal the resume logic actually needs.
func readBatteryState() -> (percent: Int, onAC: Bool)? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }

    func prop<T>(_ key: String, as type: T.Type) -> T? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? T
    }

    guard let capacity = prop("CurrentCapacity", as: Int.self),
          let maxCapacity = prop("MaxCapacity", as: Int.self),
          maxCapacity > 0 else {
        return nil
    }
    let percent = capacity * 100 / maxCapacity
    let onAC = prop("ExternalConnected", as: Bool.self) ?? false
    return (percent, onAC)
}

enum HelperError: LocalizedError {
    case unsupported(String)
    case invalidCommand

    var errorDescription: String? {
        switch self {
        case .unsupported(let message): return message
        case .invalidCommand: return "Uso: mt3k-battery-helper probe | inhibit on|off | discharge on|off | reset | bclm get|set <20-100>"
        }
    }
}

struct BatterySMC {
    let hasCH0C: Bool
    let hasCHTE: Bool
    let hasCH0I: Bool
    let hasCHIE: Bool
    let hasBCLM: Bool

    static func probe() throws -> BatterySMC {
        BatterySMC(
            hasCH0C: try SMCKit.shared.isKeyFound("CH0C"),
            hasCHTE: try SMCKit.shared.isKeyFound("CHTE"),
            hasCH0I: try SMCKit.shared.isKeyFound("CH0I"),
            hasCHIE: try SMCKit.shared.isKeyFound("CHIE"),
            hasBCLM: try SMCKit.shared.isKeyFound("BCLM")
        )
    }

    var canInhibitCharging: Bool { hasCH0C || hasCHTE }
    var canForceDischarge: Bool { hasCH0I || hasCHIE }

    func chargingInhibited() throws -> Bool {
        guard canInhibitCharging else {
            throw HelperError.unsupported("Este Mac no expone CH0C/CHTE para pausar carga.")
        }

        if hasCHTE {
            let value: UInt32 = try SMCKit.shared.read("CHTE")
            return value != 0
        }

        let value: UInt8 = try SMCKit.shared.read("CH0C")
        return value != 0
    }

    func setChargingInhibited(_ inhibited: Bool) throws {
        guard canInhibitCharging else {
            throw HelperError.unsupported("Este Mac no expone CH0C/CHTE para pausar carga.")
        }

        if !inhibited {
            try clearForceDischargeIfPresent()
        }

        if hasCHTE {
            try SMCKit.shared.write("CHTE", UInt32(inhibited ? 1 : 0))
        } else {
            try SMCKit.shared.write("CH0C", UInt8(inhibited ? 1 : 0))
        }
    }

    func forceDischarging() throws -> Bool {
        guard canForceDischarge else {
            throw HelperError.unsupported("Este Mac no expone CH0I/CHIE para descarga forzada.")
        }

        if hasCHIE {
            let data = try SMCKit.shared.readData("CHIE")
            return data.first == 0x08
        }

        let value: UInt8 = try SMCKit.shared.read("CH0I")
        return value != 0
    }

    func setForceDischarging(_ enabled: Bool) throws {
        guard canForceDischarge else {
            throw HelperError.unsupported("Este Mac no expone CH0I/CHIE para descarga forzada.")
        }

        if enabled {
            if hasCHTE {
                try SMCKit.shared.write("CHTE", UInt32(0))
            } else if hasCH0C {
                try SMCKit.shared.write("CH0C", UInt8(0))
            }
        }

        if hasCHIE {
            try SMCKit.shared.writeData("CHIE", Data([enabled ? 0x08 : 0x00]))
        } else {
            try SMCKit.shared.write("CH0I", UInt8(enabled ? 1 : 0))
        }
    }

    func reset() throws {
        if canInhibitCharging {
            try setChargingInhibited(false)
        }
        if canForceDischarge {
            try setForceDischarging(false)
        }
        if hasBCLM {
            try SMCKit.shared.write("BCLM", UInt8(100))
        }
    }

    func readBCLM() throws -> UInt8 {
        guard hasBCLM else {
            throw HelperError.unsupported("Este Mac no expone BCLM.")
        }
        return try SMCKit.shared.read("BCLM")
    }

    func setBCLM(_ limit: UInt8) throws {
        guard hasBCLM else {
            throw HelperError.unsupported("Este Mac no expone BCLM.")
        }
        guard (20...100).contains(limit) else {
            throw HelperError.unsupported("BCLM acepta 20-100.")
        }
        try SMCKit.shared.write("BCLM", limit)
    }

    private func clearForceDischargeIfPresent() throws {
        if hasCHIE {
            try SMCKit.shared.writeData("CHIE", Data([0x00]))
        } else if hasCH0I {
            try SMCKit.shared.write("CH0I", UInt8(0))
        }
    }
}

func boolArg(_ raw: String?) throws -> Bool {
    switch raw?.lowercased() {
    case "on", "true", "1", "yes": return true
    case "off", "false", "0", "no": return false
    default: throw HelperError.invalidCommand
    }
}

func printProbe(_ smc: BatterySMC) {
    let inhibited = (try? smc.chargingInhibited()) ?? false
    let discharging = (try? smc.forceDischarging()) ?? false
    let bclm = (try? smc.readBCLM()).map(String.init) ?? "unavailable"
    print("chargeInhibit=\(smc.canInhibitCharging)")
    print("forceDischarge=\(smc.canForceDischarge)")
    print("bclm=\(smc.hasBCLM)")
    print("chargingInhibited=\(inhibited)")
    print("forceDischarging=\(discharging)")
    print("bclmValue=\(bclm)")
}

func probeOutput(_ smc: BatterySMC) -> String {
    let inhibited = (try? smc.chargingInhibited()) ?? false
    let discharging = (try? smc.forceDischarging()) ?? false
    let bclm = (try? smc.readBCLM()).map(String.init) ?? "unavailable"
    return """
    chargeInhibit=\(smc.canInhibitCharging)
    forceDischarge=\(smc.canForceDischarge)
    bclm=\(smc.hasBCLM)
    chargingInhibited=\(inhibited)
    forceDischarging=\(discharging)
    bclmValue=\(bclm)
    """
}

func executeCommand(_ args: [String]) throws -> String {
    guard let command = args.first else { throw HelperError.invalidCommand }

    // The `config` command touches only persisted state, not SMC.
    if command == "config" {
        let rest = Array(args.dropFirst())
        guard let action = rest.first else { throw HelperError.invalidCommand }
        guardLock.lock()
        defer { guardLock.unlock() }
        if action == "get" {
            return "enabled=\(currentConfig.enabled)\nlimit=\(currentConfig.limit)\nresume=\(currentConfig.resume)\ntopUp=\(currentConfig.topUp)"
        }
        if action == "set", rest.count >= 4,
           let rawEnabled = Int(rest[1]), let rawLimit = Int(rest[2]), let rawResume = Int(rest[3]) {
            let limit = min(100, max(20, rawLimit))
            let resume = min(99, max(10, min(rawResume, limit - 1)))
            // Cualquier set explícito de config cancela un top-up en curso.
            currentConfig = GuardConfig(enabled: rawEnabled != 0, limit: limit, resume: resume, topUp: false)
            persistConfig(currentConfig)
            return "enabled=\(currentConfig.enabled)\nlimit=\(currentConfig.limit)\nresume=\(currentConfig.resume)\ntopUp=\(currentConfig.topUp)"
        }
        throw HelperError.invalidCommand
    }

    // `topup start|stop` — suspende/reanuda el límite sin tocar enabled/limit/resume.
    if command == "topup" {
        guard let action = args.dropFirst().first else { throw HelperError.invalidCommand }
        guardLock.lock()
        defer { guardLock.unlock() }
        if action == "start" {
            guard currentConfig.enabled else {
                throw HelperError.unsupported("Battery Guard no está activo; no hay límite que suspender.")
            }
            currentConfig.topUp = true
            persistConfig(currentConfig)
            // Levantar el inhibit ya mismo para no esperar el próximo poll (≤30 s).
            if let smc = try? BatterySMC.probe(), (try? smc.chargingInhibited()) == true {
                try? smc.setChargingInhibited(false)
            }
            logDaemon("top-up iniciado — límite suspendido hasta 100% o desconexión")
            return "topUp=true"
        }
        if action == "stop" {
            currentConfig.topUp = false
            persistConfig(currentConfig)
            logDaemon("top-up cancelado — guard rearmado")
            return "topUp=false"
        }
        throw HelperError.invalidCommand
    }

    guardLock.lock()
    defer { guardLock.unlock() }
    let smc = try BatterySMC.probe()

    switch command {
    case "probe":
        return probeOutput(smc)
    case "inhibit":
        let enabled = try boolArg(args.dropFirst().first)
        try smc.setChargingInhibited(enabled)
        // Best-effort readback: a transient SMC read error must not mask a successful write.
        let confirmed = (try? smc.chargingInhibited()) ?? enabled
        return "chargingInhibited=\(confirmed)"
    case "discharge":
        let enabled = try boolArg(args.dropFirst().first)
        try smc.setForceDischarging(enabled)
        let confirmed = (try? smc.forceDischarging()) ?? enabled
        return "forceDischarging=\(confirmed)"
    case "reset":
        try smc.reset()
        return probeOutput(smc)
    case "bclm":
        let rest = Array(args.dropFirst())
        guard let action = rest.first else { throw HelperError.invalidCommand }
        if action == "get" {
            return "bclmValue=\(try smc.readBCLM())"
        }
        if action == "set", let raw = rest.dropFirst().first, let limit = UInt8(raw) {
            try smc.setBCLM(limit)
            return "bclmValue=\(try smc.readBCLM())"
        }
        throw HelperError.invalidCommand
    default:
        throw HelperError.invalidCommand
    }
}

func makeUnixAddress(path: String) throws -> (sockaddr_un, socklen_t) {
    let encoded = Array(path.utf8CString)
    guard encoded.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
        throw HelperError.unsupported("Socket path demasiado largo.")
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for (index, byte) in encoded.enumerated() {
            buffer[index] = UInt8(bitPattern: byte)
        }
    }
    return (address, socklen_t(MemoryLayout<sockaddr_un>.size))
}

func readRequest(from fd: Int32) -> String {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 512)
    while true {
        let count = Darwin.read(fd, &buffer, buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
        if buffer.prefix(count).contains(10) { break }
        if data.count > 4096 { break }
    }
    return String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func writeResponse(_ response: String, to fd: Int32) {
    let payload = response.hasSuffix("\n") ? response : response + "\n"
    _ = payload.withCString { ptr in
        Darwin.write(fd, ptr, strlen(ptr))
    }
}

// Reads config + battery and issues a single state-change-only SMC write when needed.
// Runs on the poll thread; serialized against socket commands via guardLock.
func autonomousEvaluate() {
    guardLock.lock()
    defer { guardLock.unlock() }

    guard currentConfig.enabled else { return }
    guard let battery = readBatteryState() else { return }
    guard let smc = try? BatterySMC.probe(), smc.canInhibitCharging else { return }

    // Fin del top-up (100% o charger desconectado) → rearmar antes de decidir,
    // así el mismo ciclo de poll ya aplica el límite normal.
    if currentConfig.topUp, topUpShouldEnd(percent: battery.percent, onAC: battery.onAC) {
        currentConfig.topUp = false
        persistConfig(currentConfig)
        logDaemon("top-up terminado en \(battery.percent)% — guard rearmado (límite \(currentConfig.limit)%)")
    }

    let inhibited = (try? smc.chargingInhibited()) ?? false
    // Decisión pura en BatteryGuardCore (testeada); aquí sólo la escritura SMC.
    switch guardAction(
        percent: battery.percent,
        onAC: battery.onAC,
        chargingInhibited: inhibited,
        enabled: currentConfig.enabled,
        limit: currentConfig.limit,
        resume: currentConfig.resume,
        topUpActive: currentConfig.topUp
    ) {
    case .inhibitCharging:
        try? smc.setChargingInhibited(true)
        logDaemon("auto: carga pausada en \(battery.percent)% (límite \(currentConfig.limit)%)")
    case .resumeCharging:
        try? smc.setChargingInhibited(false)
        logDaemon("auto: carga reanudada en \(battery.percent)% (reanudar \(currentConfig.resume)%)")
    case .none:
        break
    }
}

func runDaemon() throws -> Never {
    guard getuid() == 0 else {
        throw HelperError.unsupported("El daemon de batería debe ejecutarse como root.")
    }

    currentConfig = loadConfigFromDisk()
    logDaemon("daemon iniciado · guard enabled=\(currentConfig.enabled) limit=\(currentConfig.limit) resume=\(currentConfig.resume)")

    // Autonomous enforcement loop — runs even when the app is closed.
    let pollThread = Thread {
        while true {
            Thread.sleep(forTimeInterval: 30)
            autonomousEvaluate()
        }
    }
    pollThread.stackSize = 512 * 1024
    pollThread.start()

    unlink(helperSocketPath)
    let server = socket(AF_UNIX, SOCK_STREAM, 0)
    guard server >= 0 else {
        throw HelperError.unsupported("No se pudo crear socket.")
    }

    var (address, length) = try makeUnixAddress(path: helperSocketPath)
    let bindResult = withUnsafePointer(to: &address) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(server, $0, length)
        }
    }
    guard bindResult == 0 else {
        close(server)
        throw HelperError.unsupported("No se pudo publicar socket \(helperSocketPath).")
    }

    _ = chown(helperSocketPath, 0, 20)
    _ = chmod(helperSocketPath, 0o660)

    guard listen(server, 16) == 0 else {
        close(server)
        throw HelperError.unsupported("No se pudo escuchar en socket.")
    }

    while true {
        let client = accept(server, nil, nil)
        guard client >= 0 else { continue }
        // Stalled client must not block the accept loop (and thus the poll thread's commands) forever.
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let request = readRequest(from: client)
        let args = request.split(separator: " ").map(String.init)
        do {
            let output = try executeCommand(args)
            writeResponse("ok\n\(output)", to: client)
        } catch {
            writeResponse("error\n\(error.localizedDescription)", to: client)
        }
        close(client)
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--daemon" {
        try runDaemon()
    }
    print(try executeCommand(args))
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

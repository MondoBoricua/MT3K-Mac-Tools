import Testing
import Foundation
@testable import MT3KMacTools

// MARK: - OllamaState.isCloudModel

@Suite("Detección de modelos Ollama Cloud")
struct OllamaCloudModelTests {
    @Test("Tag literal :cloud", arguments: ["glm-4.7:cloud", "qwen3-coder-next:cloud"])
    func literalCloudTag(name: String) {
        #expect(OllamaState.isCloudModel(name))
    }

    @Test("Tag con tamaño + -cloud", arguments: ["gemma4:31b-cloud", "gpt-oss:120b-cloud"])
    func sizedCloudTag(name: String) {
        #expect(OllamaState.isCloudModel(name))
    }

    @Test("Modelos locales no son cloud", arguments: ["llama3:8b", "gemma3:1b", "mistral", "cloudy:latest"])
    func localModels(name: String) {
        #expect(!OllamaState.isCloudModel(name))
    }
}

// MARK: - Catalog

@Suite("Integridad del catálogo de apps")
struct CatalogTests {
    @Test("Los ids del catálogo son únicos (un dup corrompe InstallCoordinator.statuses)")
    func uniqueIDs() {
        let ids = Catalog.items.map(\.id)
        let dupes = Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "ids duplicados: \(dupes)")
    }

    @Test("Los presets solo referencian ids que existen en el catálogo")
    @MainActor
    func presetIDsExist() {
        let catalogIDs = Set(Catalog.items.map(\.id))
        let orphanIDs = Set(AppsView.presets.flatMap(\.itemIDs)).subtracting(catalogIDs).sorted()
        #expect(orphanIDs.isEmpty, "ids huérfanos: \(orphanIDs)")
    }

    @Test("Todo appName termina en .app (detección en /Applications)")
    func appNamesWellFormed() {
        for item in Catalog.items {
            if let appName = item.appName {
                #expect(appName.hasSuffix(".app"), "\(item.id): appName '\(appName)' sin sufijo .app")
            }
        }
    }
}

// MARK: - FlowTextCleaner.stripPreamble

@Suite("Limpieza de preámbulos del LLM")
struct StripPreambleTests {
    @Test("Preámbulo con dos puntos")
    func colonPreamble() {
        #expect(FlowTextCleaner.stripPreamble("Here's the cleaned text: hola mundo") == "hola mundo")
    }

    @Test("Preámbulo Output:")
    func outputPreamble() {
        #expect(FlowTextCleaner.stripPreamble("Output: hola mundo") == "hola mundo")
    }

    @Test("Comillas envolventes")
    func wrappingQuotes() {
        #expect(FlowTextCleaner.stripPreamble("\"hola mundo\"") == "hola mundo")
    }

    @Test("Texto normal queda intacto")
    func plainTextUntouched() {
        let text = "El deploy quedó listo para mañana."
        #expect(FlowTextCleaner.stripPreamble(text) == text)
    }

    @Test("Head largo tras 'Here is' (>20 chars antes del colon) no se recorta")
    func longHeadNotStripped() {
        let text = "Here is a very long introductory clause that keeps going: body"
        #expect(FlowTextCleaner.stripPreamble(text) == text)
    }
}

// MARK: - StatsParsers

@Suite("Parser de ciclos de batería (ioreg)")
struct CycleCountTests {
    @Test("Ignora DesignCycleCount y encuentra CycleCount exacto")
    func exactKeyWins() {
        let ioreg = """
              "DesignCycleCount9C" = 1000
              "CycleCount" = 187
              "BatterySerialNumber" = "F8Y2..."
        """
        #expect(StatsParsers.cycleCount(fromIoreg: ioreg) == 187)
    }

    @Test("Salida sin CycleCount devuelve 0")
    func missingKey() {
        #expect(StatsParsers.cycleCount(fromIoreg: "\"DesignCycleCount9C\" = 1000") == 0)
    }
}

@Suite("Parsers de stats del sistema")
struct StatsParsersTests {
    @Test("CPU por delta de ticks incluye nice en user")
    func cpuFromTicks() throws {
        let cpu = try #require(StatsParsers.cpuUsage(
            fromTicks: (user: 130, sys: 220, idle: 340, nice: 20),
            previous: (user: 100, sys: 200, idle: 300, nice: 10)))
        #expect(cpu.user == 40)
        #expect(cpu.sys == 20)
        #expect(cpu.idle == 40)
    }

    @Test("CPU sin avance de ticks devuelve nil")
    func cpuTicksUnchanged() {
        #expect(StatsParsers.cpuUsage(fromTicks: (100, 200, 300, 10),
                                     previous: (100, 200, 300, 10)) == nil)
    }

    @Test("CPU con delta completamente idle")
    func cpuTicksIdle() throws {
        let cpu = try #require(StatsParsers.cpuUsage(fromTicks: (100, 200, 400, 10),
                                                    previous: (100, 200, 300, 10)))
        #expect(cpu.user == 0)
        #expect(cpu.sys == 0)
        #expect(cpu.idle == 100)
    }

    @Test("Tabla de procesos: orden, rutas con espacios y límite")
    func processTable() {
        let raw = """
        10 2.0 100 /usr/bin/first
        20 80.5 200 /Applications/My App.app/Contents/MacOS/My App
        basura sin columnas válidas
        30 10.0 900 /usr/bin/third
        40 50.0 300 /usr/bin/fourth
        50 0.0 500 /usr/bin/fifth
        """
        let table = StatsParsers.processTable(fromPS: raw, limit: 3)
        #expect(table.count == 5)
        #expect(table.topCPU.map(\.pid) == ["20", "40", "30"])
        #expect(table.topRAM.map(\.pid) == ["30", "50", "40"])
        #expect(table.topCPU.first?.name == "My App")
        #expect(table.topCPU.first?.id == "20-My App")
        #expect(table.topCPU.first?.value == "80.5%")
        #expect(table.topRAM.first?.value == StatsParsers.formatBytes(900 * 1024))
        #expect(StatsParsers.processTable(fromPS: raw, limit: 10).topCPU.count == 5)
        #expect(StatsParsers.processTable(fromPS: raw, limit: 0).topRAM.isEmpty)
    }

    @Test("CPU desde top -l 1")
    func cpuFromTop() throws {
        let top = """
        Processes: 512 total, 2 running, 510 sleeping, 2543 threads
        CPU usage: 7.89% user, 12.34% sys, 79.77% idle
        SharedLibs: 240M resident, 40M data, 20M linkedit.
        """
        let cpu = try #require(StatsParsers.cpuUsage(fromTop: top))
        #expect(cpu.user == 7.89)
        #expect(cpu.sys == 12.34)
        #expect(cpu.idle == 79.77)
    }

    @Test("Salida de top sin línea CPU devuelve nil")
    func cpuMissingLine() {
        #expect(StatsParsers.cpuUsage(fromTop: "Processes: 512 total") == nil)
    }

    @Test("Memoria desde vm_stat (page size 16384)")
    func memoryFromVMStat() {
        let vmStat = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                              100000.
        Pages active:                            200000.
        Pages inactive:                          150000.
        Pages wired down:                         50000.
        Pages occupied by compressor:             25000.
        """
        let memory = StatsParsers.memory(fromVMStat: vmStat)
        let gb = 1_073_741_824.0
        #expect(abs(memory.appGB - 200000 * 16384 / gb) < 0.001)
        #expect(abs(memory.wiredGB - 50000 * 16384 / gb) < 0.001)
        #expect(abs(memory.compressedGB - 25000 * 16384 / gb) < 0.001)
        #expect(abs(memory.usedGB - 275000 * 16384 / gb) < 0.001)
    }

    @Test("Swap desde sysctl vm.swapusage")
    func swapFromSysctl() throws {
        let raw = "vm.swapusage: total = 2048.00M  used = 512.00M  free = 1536.00M  (encrypted)"
        let swap = try #require(StatsParsers.swapGB(fromSysctl: raw))
        #expect(swap.total == 2.0)
        #expect(swap.used == 0.5)
    }

    @Test("Disco desde df -k (usa used/(used+free), no used/total)")
    func diskFromDF() throws {
        let df = """
        Filesystem    1024-blocks      Used Available Capacity iused ifree %iused  Mounted on
        /dev/disk3s5    482797652 120699413 361048239    26% 1000000 4000000   20%   /System/Volumes/Data
        """
        let disk = try #require(StatsParsers.disk(fromDF: df))
        #expect(abs(disk.totalGB - 482797652 / 1_048_576.0) < 0.01)
        #expect(abs(disk.freeGB - 361048239 / 1_048_576.0) < 0.01)
        let expectedPercent = 120699413.0 / (120699413.0 + 361048239.0) * 100
        #expect(abs(disk.usedPercent - expectedPercent) < 0.01)
    }

    @Test("Load averages desde sysctl vm.loadavg")
    func loadFromSysctl() throws {
        let load = try #require(StatsParsers.loadAverages(fromSysctl: "{ 1.23 2.34 3.45 }"))
        #expect(load.l1 == 1.23)
        #expect(load.l5 == 2.34)
        #expect(load.l15 == 3.45)
    }
}

@Suite("Parser de pmset -g batt (BatteryGuardState)")
struct BatteryReadingParserTests {
    @Test("Descargando en batería NO reporta 'charging' (bug del substring)")
    func dischargingIsNotCharging() {
        let raw = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=34930787)\t78%; discharging; 3:37 remaining present: true
        """
        let reading = BatteryGuardState.parseBattery(raw)
        #expect(reading.hasBattery)
        #expect(reading.percent == 78)
        #expect(reading.chargingState == "discharging")
        #expect(!reading.adapterConnected)
    }

    @Test("Cargando en AC reporta 'charging'")
    func chargingOnAC() {
        let raw = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=34930787)\t65%; charging; 1:12 remaining present: true
        """
        let reading = BatteryGuardState.parseBattery(raw)
        #expect(reading.chargingState == "charging")
        #expect(reading.adapterConnected)
    }

    @Test("Inhibido por Guard: 'AC attached; not charging'")
    func inhibitedNotCharging() {
        let raw = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=34930787)\t80%; AC attached; not charging present: true
        """
        let reading = BatteryGuardState.parseBattery(raw)
        #expect(reading.chargingState == "not charging")
    }

    @Test("Terminando la carga: 'finishing charge'")
    func finishingCharge() {
        let raw = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=34930787)\t99%; finishing charge; 0:05 remaining present: true
        """
        let reading = BatteryGuardState.parseBattery(raw)
        #expect(reading.chargingState == "finishing charge")
    }

    @Test("Cargado en AC sin actividad: 'charged' cae en idle")
    func chargedIdle() {
        let raw = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=34930787)\t100%; charged; 0:00 remaining present: true
        """
        let reading = BatteryGuardState.parseBattery(raw)
        #expect(reading.chargingState == "idle")
        #expect(reading.adapterConnected)
    }

    @Test("Mac sin batería interna")
    func noBattery() {
        let reading = BatteryGuardState.parseBattery("Now drawing from 'AC Power'\n")
        #expect(!reading.hasBattery)
    }
}

@Suite("Lecturas nativas del sistema")
struct SystemInfoTests {
    @Test func physicalMemory() {
        #expect(SystemInfo.physicalMemoryGB > 1)
    }

    @Test func bootTime() throws {
        let boot = try #require(SystemInfo.bootTime)
        #expect(boot < Date())
        #expect(boot > Date(timeIntervalSince1970: 946684800))
    }

    @Test func swapUsage() throws {
        let swap = try #require(SystemInfo.swapUsage)
        #expect(swap.totalGB >= swap.usedGB)
    }

    @Test func loadAverages() throws {
        let load = try #require(SystemInfo.loadAverages)
        #expect(load.l1 >= 0)
    }

    @Test func thermalLevel() {
        #expect((0...3).contains(SystemInfo.thermalLevel.state))
    }

    @Test func memoryPressure() {
        #expect(["Normal", "Warning", "Critical"].contains(SystemInfo.memoryPressure.label))
    }
}

@Suite("Ejecución de shell")
struct ShellRunnerTests {
    @Test("Drena stdout y stderr mayores al buffer del pipe")
    func drainsLargeOutput() async throws {
        let output = try await runShell(executable: "/bin/zsh", args: ["-c", """
        for ((i=0; i<10000; i++)); do
            print -r -- 'stdout-payload'
            print -ru2 -- 'stderr-payload'
        done
        """])
        #expect(output.components(separatedBy: "stdout-payload").count - 1 == 10000)
        #expect(output.components(separatedBy: "stderr-payload").count - 1 == 10000)
    }

    @Test("Propaga entorno y rechaza salida no cero")
    func environmentAndExitStatus() async throws {
        let output = try await runShell(executable: "/bin/zsh", args: ["-c", "print -rn -- $MT3K_TEST_VALUE"],
                                        extraEnv: ["MT3K_TEST_VALUE": "idle-check"])
        #expect(output == "idle-check")
        do {
            _ = try await runShell(executable: "/bin/zsh", args: ["-c", "exit 7"])
            Issue.record("Se esperaba error de salida")
        } catch {
            #expect((error as NSError).code == 7)
        }
    }
}

@Suite("Caché de métricas compartidas")
struct SystemMetricsCacheTests {
    @Test("Comparte captura en vuelo y reutiliza hasta vencer maxAge")
    @MainActor func sharedCapture() async {
        let cache = SystemMetricsCollector.MetricCache<Int>()
        var captures = 0
        var releaseCapture: CheckedContinuation<Void, Never>?
        let capture: @MainActor () async -> Int = {
            captures += 1
            if captures == 1 {
                await withCheckedContinuation { releaseCapture = $0 }
            }
            return captures
        }
        let first = Task { await cache.value(maxAge: 60, capture: capture) }
        while releaseCapture == nil { await Task.yield() }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            return await cache.value(maxAge: 0, capture: capture)
        }
        while !secondStarted { await Task.yield() }
        releaseCapture?.resume()
        let values = await (first.value, second.value)
        #expect(values.0 == 1)
        #expect(values.1 == 1)
        #expect(await cache.value(maxAge: 60, capture: capture) == 1)
        #expect(await cache.value(maxAge: 0, capture: capture) == 2)
        #expect(captures == 2)
    }

    @Test("También cachea lecturas opcionales no disponibles")
    @MainActor func missingValue() async {
        let cache = SystemMetricsCollector.MetricCache<Int?>()
        var captures = 0
        let capture: @MainActor () async -> Int? = { captures += 1; return nil }
        #expect(await cache.value(maxAge: 60, capture: capture) == nil)
        #expect(await cache.value(maxAge: 60, capture: capture) == nil)
        #expect(captures == 1)
    }
}

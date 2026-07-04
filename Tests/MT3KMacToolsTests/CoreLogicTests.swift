import Testing
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

import Foundation

/// Búsqueda en el índice completo de Homebrew (más allá del catálogo curado).
/// Los nombres salen del índice local que mantiene el propio brew; los detalles de los
/// pocos resultados visibles se piden con una sola llamada `brew info --json=v2`.
@MainActor
final class HomebrewSearch: ObservableObject {
    @Published private(set) var results: [CatalogItem] = []
    @Published private(set) var isSearching = false

    static let minimumQueryLength = 2
    static let resultLimit = 8
    private static let debounce: Duration = .milliseconds(350)

    private var caskNames: [String] = []
    private var formulaNames: [String] = []
    private var namesLoaded = false
    private var searchTask: Task<Void, Never>?

    func search(_ rawQuery: String, brewPath: String, excluding catalogPackages: Set<String>) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= Self.minimumQueryLength, !brewPath.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self, !Task.isCancelled else { return }
            await self.loadNamesIfNeeded()
            let ranked = Self.ranked(query: query, casks: self.caskNames, formulae: self.formulaNames,
                                     excluding: catalogPackages, limit: Self.resultLimit)
            let casks = ranked.filter(\.isCask).map(\.name)
            let formulae = ranked.filter { !$0.isCask }.map(\.name)
            var found: [CatalogItem] = []
            if !casks.isEmpty {
                found += Self.items(fromInfoJSON: await Self.info(brewPath: brewPath, flag: "--cask", names: casks))
            }
            if !formulae.isEmpty {
                found += Self.items(fromInfoJSON: await Self.info(brewPath: brewPath, flag: "--formula", names: formulae))
            }
            guard !Task.isCancelled else { return }
            self.results = found
            self.isSearching = false
        }
    }

    private func loadNamesIfNeeded() async {
        guard !namesLoaded else { return }
        let loaded = await Task.detached(priority: .utility) { () -> ([String], [String]) in
            let api = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/Homebrew/api")
            func lines(_ file: String) -> [String] {
                guard let text = try? String(contentsOf: api.appendingPathComponent(file), encoding: .utf8) else { return [] }
                return text.split(whereSeparator: \.isNewline).map(String.init).filter(Self.isValidPackageName)
            }
            return (lines("cask_names.txt"), lines("formula_names.txt"))
        }.value
        caskNames = loaded.0
        formulaNames = loaded.1
        // Si el índice aún no existe (brew recién instalado) se reintenta en la próxima búsqueda.
        namesLoaded = !(loaded.0.isEmpty && loaded.1.isEmpty)
    }

    private static func info(brewPath: String, flag: String, names: [String]) async -> Data {
        let env = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]
        let out = (try? await runShell(executable: brewPath, args: ["info", "--json=v2", flag] + names, extraEnv: env)) ?? ""
        return Data(out.utf8)
    }

    // MARK: - Lógica pura (testeada)

    /// Los nombres van como argumento a `brew`; sólo se aceptan tokens con la forma que usa Homebrew.
    nonisolated static func isValidPackageName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9+@._-]*$"#, options: .regularExpression) != nil
    }

    /// Casks y fórmulas ordenados juntos: nombre exacto, luego prefijo (más corto primero),
    /// luego contenido; sin los paquetes ya curados. Así un cask nunca tapa una fórmula exacta.
    nonisolated static func ranked(query: String, casks: [String], formulae: [String],
                                   excluding: Set<String>, limit: Int) -> [(name: String, isCask: Bool)] {
        guard limit > 0, !query.isEmpty else { return [] }
        var found: [(rank: Int, name: String, isCask: Bool)] = []
        for (names, isCask) in [(casks, true), (formulae, false)] {
            for name in names where !excluding.contains(name) {
                if name == query {
                    found.append((0, name, isCask))
                } else if name.hasPrefix(query) {
                    found.append((1, name, isCask))
                } else if name.contains(query) {
                    found.append((2, name, isCask))
                }
            }
        }
        found.sort { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            if a.name != b.name { return a.name < b.name }
            return a.isCask && !b.isCask
        }
        return found.prefix(limit).map { ($0.name, $0.isCask) }
    }

    /// El nombre visible viene de metadatos externos: sin caracteres de control y acotado.
    nonisolated static func displayName(_ raw: String?, fallback: String) -> String {
        let cleaned = String((raw ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(60))
    }

    /// Convierte la salida de `brew info --json=v2` en filas instalables. Descarta lo que
    /// Homebrew marca como deshabilitado o deprecado.
    nonisolated static func items(fromInfoJSON data: Data) -> [CatalogItem] {
        struct Info: Decodable {
            struct Cask: Decodable {
                let token: String
                let name: [String]?
                let desc: String?
                let deprecated: Bool?
                let disabled: Bool?
                let artifacts: [[String: AnyDecodable]]?
            }
            struct Formula: Decodable {
                let name: String
                let desc: String?
                let deprecated: Bool?
                let disabled: Bool?
            }
            let casks: [Cask]?
            let formulae: [Formula]?
        }
        guard let info = try? JSONDecoder().decode(Info.self, from: data) else { return [] }
        var items: [CatalogItem] = []
        for cask in info.casks ?? [] where cask.disabled != true && cask.deprecated != true && isValidPackageName(cask.token) {
            var appName: String?
            var needsAdmin = false
            for artifact in cask.artifacts ?? [] {
                if artifact["pkg"] != nil || artifact["installer"] != nil { needsAdmin = true }
                if appName == nil, case .array(let apps)? = artifact["app"]?.value {
                    for entry in apps {
                        if case .string(let path) = entry { appName = (path as NSString).lastPathComponent }
                        if case .object(let options) = entry, case .string(let target)? = options["target"] {
                            appName = (target as NSString).lastPathComponent
                        }
                    }
                }
            }
            items.append(CatalogItem(
                id: "brew-cask:\(cask.token)",
                name: displayName(cask.name?.first, fallback: cask.token),
                description: displayName(cask.desc, fallback: "Cask de Homebrew."),
                symbol: "shippingbox.fill",
                install: .brewCask(cask.token),
                category: .utilities,
                appName: appName,
                requiresAdminInstall: needsAdmin
            ))
        }
        for formula in info.formulae ?? [] where formula.disabled != true && formula.deprecated != true && isValidPackageName(formula.name) {
            items.append(CatalogItem(
                id: "brew-formula:\(formula.name)",
                name: formula.name,
                description: displayName(formula.desc, fallback: "Fórmula de Homebrew."),
                symbol: "terminal.fill",
                install: .brewFormula(formula.name),
                category: .utilities
            ))
        }
        return items
    }
}

/// JSON heterogéneo mínimo para leer los artifacts de un cask.
struct AnyDecodable: Decodable {
    indirect enum Value {
        case string(String)
        case array([Value])
        case object([String: Value])
        case other
    }
    let value: Value

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = .string(string)
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = .array(array.map(\.value))
        } else if let object = try? container.decode([String: AnyDecodable].self) {
            value = .object(object.mapValues(\.value))
        } else {
            value = .other
        }
    }
}

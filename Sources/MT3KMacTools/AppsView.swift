import SwiftUI
import AppKit

struct AppsView: View {
    @EnvironmentObject var brew: BrewState
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var installer: InstallCoordinator

    @State private var brewBusy = false
    @State private var query = ""
    @State private var selectedCategory: CatalogCategory? = nil
    @State private var methodFilter: MethodFilter = .all
    @State private var visibilityFilter: VisibilityFilter = .all
    @State private var selectedIDs = Set<String>()
    @State private var confirmSecurityQueue = false
    @AppStorage("showAdvancedTools") private var showAdvancedTools = true
    @AppStorage("confirmSecurityTools") private var confirmSecurityTools = true

    enum MethodFilter: String, CaseIterable, Identifiable {
        case all = "Todo"
        case brew = "Brew"
        case npm = "npm"
        case direct = "DMG/GitHub"
        case terminal = "Terminal"

        var id: String { rawValue }
    }

    enum VisibilityFilter: String, CaseIterable, Identifiable {
        case all = "Todo"
        case notInstalled = "No instalado"
        case installed = "Instalado"
        case updates = "Updates"
        case admin = "Requiere admin"
        case cli = "CLI"

        var id: String { rawValue }
    }

    struct Preset: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let itemIDs: [String]

        var items: [CatalogItem] {
            itemIDs.compactMap { id in Catalog.items.first { $0.id == id } }
        }
    }

    private let presets: [Preset] = [
        .init(
            id: "developer",
            title: "Developer base",
            symbol: "hammer.fill",
            itemIDs: ["git", "gh", "vscode", "cursor", "zed", "node", "iterm2", "ghostty", "orbstack"]
        ),
        .init(
            id: "ai-coding",
            title: "AI coding",
            symbol: "sparkles",
            itemIDs: ["claude", "chatgpt", "claude-code", "codex-cli", "codex-desktop", "ollama", "lmstudio", "cursor", "windsurf"]
        ),
        .init(
            id: "security",
            title: "Security toolkit",
            symbol: "lock.shield.fill",
            itemIDs: ["wireshark", "burp-suite", "owasp-zap", "proxyman", "nmap", "ffuf", "sqlmap", "hashcat", "john", "hydra"]
        ),
        .init(
            id: "creator",
            title: "Creator",
            symbol: "paintbrush.pointed.fill",
            itemIDs: ["figma", "sketch", "affinity-designer", "affinity-photo", "blender", "krita", "obs"]
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                dashboard
                preflight
                presetsView
                filterBar
                queueBar
                ForEach(visibleCategories) { category in
                    let items = filteredItems(in: category)
                    if !items.isEmpty {
                        categorySection(title: category.rawValue, symbol: category.symbol, items: items)
                    }
                }
                if filteredItems.isEmpty {
                    emptyState
                }
                LogView()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .alert("Instalar security toolkit", isPresented: $confirmSecurityQueue) {
            Button("Instalar") {
                Task { await installer.installQueue(selectedItems, log: log) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La selección incluye herramientas de red, auditoría o pentesting. Úsalas solo en sistemas donde tengas autorización.")
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    dashboardText
                    Spacer()
                    dashboardStats
                }
                VStack(alignment: .leading, spacing: 14) {
                    dashboardText
                    dashboardStats
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bgCard)
        .overlay(Rectangle().frame(width: 4).foregroundColor(Theme.blue), alignment: .leading)
        .cornerRadius(12)
    }

    private var dashboardText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPS").font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Theme.accent)
            Text("Preparar este Mac").font(.title2).bold()
            Text("Selecciona un preset, filtra el catálogo o arma una cola manual de instalación.")
                .foregroundColor(Theme.textSecondary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dashboardStats: some View {
        HStack(spacing: 14) {
            dashboardStat(title: "Catálogo", value: "\(Catalog.items.count)", symbol: "square.grid.2x2.fill", color: Theme.blue)
            dashboardStat(title: "Seleccionado", value: "\(selectedIDs.count)", symbol: "checklist", color: Theme.green)
            dashboardStat(title: "Updates", value: "\(outdatedCatalogCount)", symbol: "arrow.down.circle.fill", color: Theme.orange)
            dashboardStat(title: "Terminal", value: "\(Catalog.items.filter(\.requiresAdminInstall).count)", symbol: "apple.terminal.fill", color: Theme.amber)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dashboardStat(title: String, value: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.headline)
                Text(title).font(.caption2).foregroundColor(Theme.textSecondary)
            }
        }
        .frame(minWidth: 92, alignment: .leading)
    }

    private var preflight: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pre-requisitos").font(.headline)
                Spacer()
                Button {
                    Task { await brew.refresh() }
                } label: {
                    HStack(spacing: 4) {
                        if brew.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Re-verificar")
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(Theme.blue)
                .font(.caption)
            }

            PreflightRow(
                ok: brew.brewInstalled,
                title: "Homebrew",
                detail: brew.brewInstalled ? brew.brewPath : "no detectado en /opt/homebrew o /usr/local",
                actionLabel: brew.brewInstalled ? nil : "Instalar Homebrew",
                disabled: brewBusy
            ) {
                Task { await installBrew() }
            }

            if brew.brewInstalled {
                HStack(spacing: 10) {
                    Image(systemName: outdatedCatalogCount > 0 ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(outdatedCatalogCount > 0 ? Theme.orange : Theme.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates de catálogo").bold()
                        Text(outdatedCatalogCount > 0 ? "\(outdatedCatalogCount) items tienen update vía Homebrew" : "Todo lo detectado está al día")
                            .foregroundColor(Theme.textSecondary)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Re-verificar") {
                        Task { await brew.refresh() }
                    }
                    .disabled(brew.isRefreshing)
                }
            }

            PreflightRow(
                ok: brew.nodeInstalled,
                title: "Node.js",
                detail: brew.nodeInstalled ? brew.nodePath : "necesario para CLIs vía npm (OpenDesign, Pencil CLI)",
                actionLabel: (!brew.nodeInstalled && brew.brewInstalled) ? "Instalar Node.js" : nil,
                disabled: brewBusy
            ) {
                Task { await installNode() }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var presetsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Presets").font(.headline)
                Spacer()
                Button("Limpiar selección") {
                    selectedIDs.removeAll()
                }
                .buttonStyle(.borderless)
                .disabled(selectedIDs.isEmpty || installer.isRunningQueue)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                ForEach(presets) { preset in
                    Button {
                        selectedIDs.formUnion(preset.items.map(\.id))
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: preset.symbol)
                                .foregroundColor(Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title).font(.subheadline).bold()
                                Text("\(preset.items.count) items")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundColor(Theme.blue)
                        }
                        .padding(12)
                        .background(Theme.bgDark.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                        .clipShape(.rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(installer.isRunningQueue)
                }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.textSecondary)
                TextField("Buscar apps, CLIs o descripciones", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(10)
            .background(Theme.bgDark.opacity(0.65))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            .clipShape(.rect(cornerRadius: 8))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    categoryPicker
                    methodPicker
                    visibilityPicker
                }
                VStack(alignment: .leading, spacing: 10) {
                    categoryPicker
                    methodPicker
                    visibilityPicker
                }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var categoryPicker: some View {
        Picker("Categoría", selection: $selectedCategory) {
            Text("Todas").tag(CatalogCategory?.none)
            ForEach(availableCategories) { category in
                Text(category.rawValue).tag(CatalogCategory?.some(category))
            }
        }
        .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
    }

    private var methodPicker: some View {
        Picker("Método", selection: $methodFilter) {
            ForEach(MethodFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 520)
    }

    private var visibilityPicker: some View {
        Picker("Vista", selection: $visibilityFilter) {
            ForEach(VisibilityFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 620)
    }

    private var queueBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    queueText
                    Spacer()
                    queueActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    queueText
                    queueActions
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var queueText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(installer.isRunningQueue ? "Cola corriendo" : "Cola de instalación")
                .font(.headline)
            Text(queueSummary)
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var queueActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                selectVisibleButton
                removeVisibleButton
                installSelectionButton
            }
            VStack(alignment: .leading, spacing: 8) {
                selectVisibleButton
                removeVisibleButton
                installSelectionButton
            }
        }
    }

    private var selectVisibleButton: some View {
        Button {
            selectedIDs.formUnion(filteredItems.map(\.id))
        } label: {
            Label("Seleccionar visibles", systemImage: "checkmark.circle")
        }
        .disabled(filteredItems.isEmpty || installer.isRunningQueue)
    }

    private var removeVisibleButton: some View {
        Button {
            selectedIDs.subtract(filteredItems.map(\.id))
        } label: {
            Label("Quitar visibles", systemImage: "minus.circle")
        }
        .disabled(filteredItems.isEmpty || installer.isRunningQueue)
    }

    private var installSelectionButton: some View {
        Button {
            if selectedItems.contains(where: { $0.category == .cybersec }) && confirmSecurityTools {
                confirmSecurityQueue = true
            } else {
                Task { await installer.installQueue(selectedItems, log: log) }
            }
        } label: {
            if installer.isRunningQueue {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Instalando")
                }
            } else {
                Label("Instalar selección", systemImage: "play.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedItems.isEmpty || installer.isRunningQueue)
    }

    private func categorySection(title: String, symbol: String, items: [CatalogItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundColor(Theme.accent)
                Text(title).font(.headline)
                Spacer()
                Text("\(items.count) apps").font(.caption).foregroundColor(Theme.textSecondary)
            }
            .padding(.bottom, 4)
            ForEach(items) { item in
                InstallRow(
                    item: item,
                    isSelected: selectedIDs.contains(item.id),
                    selectionEnabled: canInstall(item),
                    onSelectionChange: { isSelected in
                        if isSelected {
                            selectedIDs.insert(item.id)
                        } else {
                            selectedIDs.remove(item.id)
                        }
                    }
                )
                if item.id != items.last?.id {
                    Divider().background(Theme.border)
                }
            }
        }
        .padding(20)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(Theme.textSecondary)
            Text("Sin resultados").font(.headline)
            Text("Ajusta la búsqueda o los filtros para ver más items.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(Theme.bgCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }

    private var visibleCategories: [CatalogCategory] {
        if let selectedCategory, availableCategories.contains(selectedCategory) {
            return [selectedCategory]
        }
        return availableCategories
    }

    private var availableCategories: [CatalogCategory] {
        CatalogCategory.allCases.filter { category in
            category != .browsers && (showAdvancedTools || category != .cybersec)
        }
    }

    private var filteredItems: [CatalogItem] {
        visibleCategories.flatMap { filteredItems(in: $0) }
    }

    private var selectedItems: [CatalogItem] {
        Catalog.items.filter { selectedIDs.contains($0.id) && canInstall($0) }
    }

    private var queueSummary: String {
        if selectedItems.isEmpty {
            return "Selecciona apps individuales, visibles o presets para armar una cola."
        }
        let terminalCount = selectedItems.filter(\.requiresAdminInstall).count
        if terminalCount > 0 {
            return "\(selectedItems.count) items seleccionados; \(terminalCount) abrirán Terminal para sudo."
        }
        return "\(selectedItems.count) items listos para instalar en secuencia."
    }

    private var outdatedCatalogCount: Int {
        Catalog.items.filter { brew.isOutdated($0.install) }.count
    }

    private func filteredItems(in category: CatalogCategory) -> [CatalogItem] {
        Catalog.items(in: category).filter { item in
            matchesQuery(item) &&
            matchesMethod(item) &&
            matchesVisibility(item)
        }
    }

    private func matchesQuery(_ item: CatalogItem) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = "\(item.name) \(item.description) \(item.install.label) \(item.category.rawValue)".lowercased()
        return haystack.contains(trimmed.lowercased())
    }

    private func matchesMethod(_ item: CatalogItem) -> Bool {
        switch methodFilter {
        case .all: return true
        case .brew:
            switch item.install {
            case .brewCask, .brewFormula, .brewTap: return true
            default: return false
            }
        case .npm:
            if case .npm = item.install { return true }
            return false
        case .direct:
            switch item.install {
            case .dmg, .githubLatest: return true
            default: return false
            }
        case .terminal:
            return item.requiresAdminInstall
        }
    }

    private func matchesVisibility(_ item: CatalogItem) -> Bool {
        switch visibilityFilter {
        case .all: return true
        case .notInstalled: return !appExists(item)
        case .installed: return appExists(item)
        case .updates: return brew.isOutdated(item.install)
        case .admin: return item.requiresAdminInstall
        case .cli: return item.appName == nil
        }
    }

    private func appExists(_ item: CatalogItem) -> Bool {
        guard let appName = item.appName else { return false }
        return FileManager.default.fileExists(atPath: "/Applications/\(appName)")
    }

    private func canInstall(_ item: CatalogItem) -> Bool {
        switch item.install {
        case .brewCask, .brewFormula, .brewTap: return brew.brewInstalled
        case .npm: return brew.nodeInstalled
        case .dmg, .githubLatest: return true
        }
    }

    @MainActor
    private func installBrew() async {
        brewBusy = true
        defer { brewBusy = false }
        log.append("Abriendo Terminal para instalar Homebrew...", level: .info)
        do {
            let script = try resolveScript("install_brew.sh")
            try openInTerminal(scriptPath: script.path)
            log.append("Terminal abierto. Cuando termine, pulsa 'Re-verificar'.", level: .info)
        } catch {
            log.append("Error: \(error.localizedDescription)", level: .error)
        }
    }

    @MainActor
    private func installNode() async {
        brewBusy = true
        defer { brewBusy = false }
        log.append("Instalando Node.js via Homebrew...", level: .info)
        do {
            let script = try resolveScript("install_package.sh")
            let output = try await runShell(executable: "/bin/zsh", args: [script.path, "formula", "node"])
            log.append(output.split(separator: "\n").suffix(1).joined(), level: .success)
            await brew.refresh()
        } catch {
            log.append("Error: \(error.localizedDescription)", level: .error)
        }
    }
}

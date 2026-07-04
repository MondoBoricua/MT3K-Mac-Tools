import SwiftUI
import AppKit

struct DevView: View {
    @EnvironmentObject var brew: BrewState
    @EnvironmentObject var log: LogStore

    @State private var snapshot = DevSnapshot.empty
    @State private var isRefreshing = false
    @State private var gitName = ""
    @State private var gitEmail = ""
    @State private var dotfilesRepo = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                healthGrid
                xcodeSection
                gitSection
                sshSection
                brewBundleSection
                shellSection
                OllamaPanel()
                dotfilesSection
                LogView()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .task { await refresh() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DEV").font(.system(size: 11, weight: .bold)).tracking(1).foregroundColor(Theme.accent)
                Text("Centro de setup developer").font(.title2).bold()
                Text("Verifica el toolchain, configura Git/GitHub/SSH, exporta Brewfile y prepara shell/dotfiles.")
                    .foregroundColor(Theme.textSecondary)
                    .font(.subheadline)
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                HStack(spacing: 6) {
                    if isRefreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    Text("Re-verificar")
                }
            }
            .buttonStyle(.borderless)
            .foregroundColor(Theme.blue)
            .disabled(isRefreshing)
        }
        .padding(20)
        .background(Theme.bgCard)
        .overlay(Rectangle().frame(width: 4).foregroundColor(Theme.accent), alignment: .leading)
        .cornerRadius(12)
    }

    private var healthGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            HealthTile(title: "Homebrew", detail: snapshot.brewPath, ok: !snapshot.brewPath.isEmpty, symbol: "shippingbox.fill")
            HealthTile(title: "Xcode CLT", detail: snapshot.xcodePath, ok: snapshot.hasXcodeCLT, symbol: "hammer.fill")
            HealthTile(title: "Git", detail: snapshot.gitVersion, ok: !snapshot.gitVersion.isEmpty, symbol: "arrow.triangle.branch")
            HealthTile(title: "GitHub", detail: snapshot.ghStatus, ok: snapshot.ghAuthenticated, symbol: "person.crop.circle.badge.checkmark")
            HealthTile(title: "SSH", detail: snapshot.sshDetail, ok: snapshot.hasSSHKey, symbol: "key.fill")
            HealthTile(title: "PATH", detail: snapshot.pathDetail, ok: snapshot.pathOK, symbol: "point.topleft.down.curvedto.point.bottomright.up")
            HealthTile(title: "Node", detail: snapshot.nodeVersion, ok: !snapshot.nodeVersion.isEmpty, symbol: "hexagon.fill")
            HealthTile(title: "Python", detail: snapshot.pythonVersion, ok: !snapshot.pythonVersion.isEmpty, symbol: "chevron.left.forwardslash.chevron.right")
            HealthTile(title: "Rust", detail: snapshot.rustVersion, ok: !snapshot.rustVersion.isEmpty, symbol: "gearshape.fill")
            HealthTile(title: "Java", detail: snapshot.javaVersion, ok: !snapshot.javaVersion.isEmpty, symbol: "cup.and.saucer.fill")
        }
    }

    private var xcodeSection: some View {
        DevPanel(title: "Xcode Command Line Tools", symbol: "hammer.fill") {
            DevInfoRow(label: "xcode-select", value: snapshot.xcodePath.isEmpty ? "No instalado" : snapshot.xcodePath)
            DevInfoRow(label: "clang", value: snapshot.clangVersion.isEmpty ? "No detectado" : snapshot.clangVersion)
            DevInfoRow(label: "swift", value: snapshot.swiftVersion.isEmpty ? "No detectado" : snapshot.swiftVersion)
            actionRow {
                DevActionButton(title: "Instalar CLT", symbol: "arrow.down.circle.fill", color: Theme.blue) {
                    Task { await runAndRefresh("Abriendo instalador de Xcode CLT...", "/usr/bin/xcode-select --install") }
                }
                DevActionButton(title: "Reset xcode-select", symbol: "wrench.adjustable.fill", color: Theme.amber) {
                    openTerminalCommand("sudo /usr/bin/xcode-select --reset", title: "Reset Xcode Select")
                }
            }
        }
    }

    private var gitSection: some View {
        DevPanel(title: "Git y GitHub", symbol: "arrow.triangle.branch") {
            DevInfoRow(label: "Git", value: snapshot.gitVersion.isEmpty ? "No detectado" : snapshot.gitVersion)
            DevInfoRow(label: "Usuario", value: snapshot.gitUserDisplay)
            HStack(spacing: 10) {
                TextField("Nombre Git", text: $gitName)
                    .textFieldStyle(.roundedBorder)
                TextField("Email Git", text: $gitEmail)
                    .textFieldStyle(.roundedBorder)
            }
            actionRow {
                DevActionButton(title: "Guardar Git", symbol: "checkmark.circle.fill", color: Theme.green) {
                    Task { await saveGitIdentity() }
                }
                DevActionButton(title: "Defaults sanos", symbol: "slider.horizontal.3", color: Theme.blue) {
                    Task { await applyGitDefaults() }
                }
                DevActionButton(title: "gh auth login", symbol: "person.crop.circle.badge.plus", color: Theme.amber) {
                    openTerminalCommand("gh auth login", title: "GitHub Auth")
                }
                DevActionButton(title: "gh auth status", symbol: "checkmark.shield.fill", color: Theme.green) {
                    Task { await runAndRefresh("Verificando GitHub CLI...", "gh auth status") }
                }
            }
        }
    }

    private var sshSection: some View {
        DevPanel(title: "SSH Keys", symbol: "key.fill") {
            DevInfoRow(label: "Llaves", value: snapshot.sshDetail)
            DevInfoRow(label: "GitHub SSH", value: snapshot.sshGitHubStatus)
            actionRow {
                DevActionButton(title: "Crear ed25519", symbol: "key.viewfinder", color: Theme.blue) {
                    Task { await createSSHKey() }
                }
                DevActionButton(title: "Copiar public key", symbol: "doc.on.doc.fill", color: Theme.green) {
                    copyPublicKey()
                }
                DevActionButton(title: "Abrir GitHub Keys", symbol: "arrow.up.right.square.fill", color: Theme.blue) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/settings/keys")!)
                }
                DevActionButton(title: "Probar SSH", symbol: "network", color: Theme.amber) {
                    Task { await testGitHubSSH() }
                }
            }
        }
    }

    private var brewBundleSection: some View {
        DevPanel(title: "Brew Bundle", symbol: "shippingbox.and.arrow.backward.fill") {
            DevInfoRow(label: "Brewfile", value: snapshot.brewfilePath)
            actionRow {
                DevActionButton(title: "Exportar Brewfile", symbol: "square.and.arrow.down.fill", color: Theme.green) {
                    Task { await dumpBrewfile() }
                }
                DevActionButton(title: "Restaurar Brewfile", symbol: "arrow.clockwise.circle.fill", color: Theme.amber) {
                    openTerminalCommand("brew bundle install --file=\"$HOME/Brewfile\"", title: "Brew Bundle Install")
                }
                DevActionButton(title: "Abrir Brewfile", symbol: "doc.text.fill", color: Theme.blue) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Brewfile"))
                }
            }
        }
    }

    private var shellSection: some View {
        DevPanel(title: "Shell y Terminal", symbol: "terminal.fill") {
            DevInfoRow(label: "Shell actual", value: snapshot.currentShell)
            DevInfoRow(label: "fish", value: snapshot.fishPath.isEmpty ? "No instalado" : snapshot.fishPath)
            DevInfoRow(label: "Oh My Posh", value: snapshot.ohMyPoshVersion.isEmpty ? "No detectado" : snapshot.ohMyPoshVersion)
            actionRow {
                DevActionButton(title: "Hacer fish default", symbol: "fish.fill", color: Theme.blue) {
                    openTerminalCommand("""
                    FISH_PATH="$(command -v fish)"
                    if [ -z "$FISH_PATH" ]; then echo "fish no está instalado"; exit 1; fi
                    grep -qxF "$FISH_PATH" /etc/shells || echo "$FISH_PATH" | sudo tee -a /etc/shells
                    chsh -s "$FISH_PATH"
                    """, title: "Set Fish Shell")
                }
                DevActionButton(title: "Ver PATH", symbol: "list.bullet.rectangle.fill", color: Theme.green) {
                    Task { await runAndRefresh("PATH actual", "printf '%s\\n' \"$PATH\" | tr ':' '\\n'") }
                }
                DevActionButton(title: "Abrir config fish", symbol: "folder.fill", color: Theme.blue) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/fish"))
                }
                DevActionButton(title: "Aplicar tema Night Owl", symbol: "moon.stars.fill", color: Theme.accent) {
                    Task { await applyNightOwlTheme() }
                }
            }
        }
    }

    private var dotfilesSection: some View {
        DevPanel(title: "Dotfiles", symbol: "folder.badge.gearshape") {
            DevInfoRow(label: "Destino", value: "~/.dotfiles")
            DevInfoRow(label: "Estado", value: snapshot.dotfilesStatus)
            Text("Opcional, pero recomendado: usa un repo privado de GitHub para tus dotfiles. Así tienes backup automático de tu shell, Git, Brewfile y configs sin exponer tokens, emails, rutas o secretos en público.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Repo de dotfiles (https://github.com/usuario/dotfiles.git)", text: $dotfilesRepo)
                .textFieldStyle(.roundedBorder)
            actionRow {
                DevActionButton(title: "Clonar", symbol: "arrow.down.doc.fill", color: Theme.blue) {
                    Task { await cloneDotfiles() }
                }
                .disabled(dotfilesRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                DevActionButton(title: "Crear base", symbol: "plus.rectangle.fill", color: Theme.blue) {
                    Task { await createDotfilesStarter() }
                }
                DevActionButton(title: "Backup comunes", symbol: "archivebox.fill", color: Theme.green) {
                    Task { await backupCommonDotfiles() }
                }
                DevActionButton(title: "Ejecutar bootstrap", symbol: "play.fill", color: Theme.amber) {
                    openTerminalCommand(dotfilesBootstrapCommand, title: "Dotfiles Bootstrap")
                }
                .disabled(!snapshot.hasDotfilesDirectory)
                DevActionButton(title: "Abrir carpeta", symbol: "folder.fill", color: Theme.blue) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".dotfiles"))
                }
                .disabled(!snapshot.hasDotfilesDirectory)
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
        snapshot = await DevSnapshot.capture()
        gitName = snapshot.gitName
        gitEmail = snapshot.gitEmail
    }

    private func saveGitIdentity() async {
        let name = gitName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = gitEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !email.isEmpty else {
            log.append("Git: nombre y email son requeridos.", level: .warn)
            return
        }
        await runAndRefresh("Guardando identidad Git...", "git config --global user.name \(name.shellQuoted) && git config --global user.email \(email.shellQuoted)")
    }

    private func applyGitDefaults() async {
        await runAndRefresh("Aplicando defaults Git...", """
        git config --global init.defaultBranch main
        git config --global color.ui auto
        git config --global pull.rebase false
        git config --global fetch.prune true
        """)
    }

    private func createSSHKey() async {
        let email = gitEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = email.isEmpty ? "\(NSUserName())@\(Host.current().localizedName ?? "mac")" : email
        await runAndRefresh("Creando llave SSH ed25519...", """
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        if [ -f "$HOME/.ssh/id_ed25519" ]; then
          echo "Ya existe ~/.ssh/id_ed25519"
        else
          ssh-keygen -t ed25519 -C \(comment.shellQuoted) -f "$HOME/.ssh/id_ed25519" -N ""
        fi
        """)
    }

    private func copyPublicKey() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/id_ed25519.pub")
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            log.append("No encontré ~/.ssh/id_ed25519.pub para copiar.", level: .warn)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
        log.append("Public key copiada al clipboard.", level: .success)
    }

    private func testGitHubSSH() async {
        await runAndRefresh("Probando SSH contra GitHub...", "ssh -o BatchMode=yes -T git@github.com 2>&1 || true")
    }

    private func dumpBrewfile() async {
        await runAndRefresh("Exportando ~/Brewfile...", "brew bundle dump --file=\"$HOME/Brewfile\" --force")
    }

    private func cloneDotfiles() async {
        let repo = dotfilesRepo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else {
            log.append("Pega el repo de dotfiles primero.", level: .warn)
            return
        }
        await runAndRefresh("Clonando dotfiles en ~/.dotfiles...", """
        if [ -d "$HOME/.dotfiles/.git" ]; then
          git -C "$HOME/.dotfiles" pull --ff-only
        else
          git clone \(repo.shellQuoted) "$HOME/.dotfiles"
        fi
        """)
    }

    private func backupCommonDotfiles() async {
        await runAndRefresh("Creando backup de dotfiles comunes...", """
        backup="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup"
        for f in .zshrc .zprofile .gitconfig .config/fish/config.fish .config/oh-my-posh; do
          [ -e "$HOME/$f" ] && mkdir -p "$backup/$(dirname "$f")" && cp -R "$HOME/$f" "$backup/$f"
        done
        echo "$backup"
        """)
    }

    private func createDotfilesStarter() async {
        await runAndRefresh("Creando estructura base en ~/.dotfiles...", """
        set -e
        mkdir -p "$HOME/.dotfiles"/{fish,git,ssh,brew}
        [ -f "$HOME/.dotfiles/README.md" ] || cat > "$HOME/.dotfiles/README.md" <<'EOF'
        # Dotfiles privados

        Repo privado para respaldar y restaurar el setup del Mac.

        Recomendado:
        - Mantener este repo privado.
        - No subir tokens, claves privadas SSH, archivos `.env`, cookies ni secretos.
        - Guardar aquí configs reproducibles: shell, Git, Brewfile, aliases y scripts.
        EOF
        [ -f "$HOME/.dotfiles/.gitignore" ] || cat > "$HOME/.dotfiles/.gitignore" <<'EOF'
        .DS_Store
        *.local
        *.secret
        *.key
        id_*
        .env
        EOF
        [ -f "$HOME/.dotfiles/install.sh" ] || cat > "$HOME/.dotfiles/install.sh" <<'EOF'
        #!/bin/zsh
        set -e

        repo="$HOME/.dotfiles"
        backup="$HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup"

        link_file() {
          src="$1"
          dst="$2"
          [ -e "$src" ] || return 0
          if [ -e "$dst" ] || [ -L "$dst" ]; then
            mkdir -p "$backup/$(dirname "${dst#$HOME/}")"
            mv "$dst" "$backup/${dst#$HOME/}"
          fi
          mkdir -p "$(dirname "$dst")"
          ln -s "$src" "$dst"
        }

        link_file "$repo/git/.gitconfig" "$HOME/.gitconfig"
        link_file "$repo/fish/config.fish" "$HOME/.config/fish/config.fish"

        echo "Dotfiles aplicados. Backup: $backup"
        EOF
        chmod +x "$HOME/.dotfiles/install.sh"
        [ -f "$HOME/.dotfiles/brew/Brewfile" ] || (brew bundle dump --file="$HOME/.dotfiles/brew/Brewfile" --force 2>/dev/null || true)
        [ -f "$HOME/.dotfiles/git/.gitconfig" ] || ([ -f "$HOME/.gitconfig" ] && cp "$HOME/.gitconfig" "$HOME/.dotfiles/git/.gitconfig" || true)
        [ -f "$HOME/.dotfiles/fish/config.fish" ] || ([ -f "$HOME/.config/fish/config.fish" ] && cp "$HOME/.config/fish/config.fish" "$HOME/.dotfiles/fish/config.fish" || touch "$HOME/.dotfiles/fish/config.fish")
        echo "$HOME/.dotfiles"
        """)
    }

    private var dotfilesBootstrapCommand: String {
        """
        cd "$HOME/.dotfiles" || { echo "~/.dotfiles no existe"; exit 1; }
        if [ -x "./install.sh" ]; then ./install.sh
        elif [ -x "./bootstrap.sh" ]; then ./bootstrap.sh
        elif [ -f "./install.sh" ]; then chmod +x ./install.sh && ./install.sh
        elif [ -f "./bootstrap.sh" ]; then chmod +x ./bootstrap.sh && ./bootstrap.sh
        else echo "No encontré install.sh ni bootstrap.sh en ~/.dotfiles"; exit 1
        fi
        """
    }

    private func applyNightOwlTheme() async {
        let cmd = """
        set -e
        THEME_DIR="$HOME/.poshthemes"
        THEME_FILE="$THEME_DIR/night-owl.omp.json"
        mkdir -p "$THEME_DIR"

        if ! command -v oh-my-posh >/dev/null 2>&1; then
            if command -v brew >/dev/null 2>&1; then
                echo "Instalando oh-my-posh via brew..."
                brew install oh-my-posh
            else
                echo "✗ oh-my-posh no está instalado y brew no está disponible. Instala Homebrew primero."
                exit 1
            fi
        fi

        if [ ! -f "$THEME_FILE" ]; then
            echo "Descargando night-owl.omp.json..."
            curl -fsSL "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/night-owl.omp.json" -o "$THEME_FILE"
            echo "✓ Tema guardado en $THEME_FILE"
        else
            echo "✓ Tema ya existe en $THEME_FILE"
        fi

        ZSHRC="$HOME/.zshrc"
        LINE_ZSH='eval "$(oh-my-posh init zsh --config ~/.poshthemes/night-owl.omp.json)"'
        touch "$ZSHRC"
        if ! grep -Fq "$LINE_ZSH" "$ZSHRC" 2>/dev/null; then
            printf '\\n# oh-my-posh — night-owl theme\\n%s\\n' "$LINE_ZSH" >> "$ZSHRC"
            echo "✓ Eval añadido a ~/.zshrc"
        else
            echo "✓ ~/.zshrc ya tiene el eval de night-owl"
        fi

        FISH_CFG="$HOME/.config/fish/config.fish"
        if [ -d "$HOME/.config/fish" ] || command -v fish >/dev/null 2>&1; then
            mkdir -p "$HOME/.config/fish"
            touch "$FISH_CFG"
            LINE_FISH='oh-my-posh init fish --config ~/.poshthemes/night-owl.omp.json | source'
            if ! grep -Fq "$LINE_FISH" "$FISH_CFG" 2>/dev/null; then
                printf '\\n# oh-my-posh — night-owl theme\\n%s\\n' "$LINE_FISH" >> "$FISH_CFG"
                echo "✓ Init añadido a config.fish"
            else
                echo "✓ config.fish ya tiene el init de night-owl"
            fi
        fi

        echo ""
        echo "Listo. Reinicia tu terminal o ejecuta: exec \\$SHELL -l"
        """
        await runAndRefresh("Aplicando tema Night Owl...", cmd)
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

private struct DevSnapshot {
    var brewPath: String
    var xcodePath: String
    var clangVersion: String
    var swiftVersion: String
    var gitVersion: String
    var gitName: String
    var gitEmail: String
    var ghStatus: String
    var ghAuthenticated: Bool
    var hasSSHKey: Bool
    var sshDetail: String
    var sshGitHubStatus: String
    var pathDetail: String
    var pathOK: Bool
    var nodeVersion: String
    var pythonVersion: String
    var rustVersion: String
    var javaVersion: String
    var fishPath: String
    var currentShell: String
    var ohMyPoshVersion: String
    var brewfilePath: String
    var hasDotfilesDirectory: Bool
    var dotfilesStatus: String

    var hasXcodeCLT: Bool { !xcodePath.isEmpty && xcodePath != "No instalado" }
    var gitUserDisplay: String {
        if gitName.isEmpty && gitEmail.isEmpty { return "No configurado" }
        return "\(gitName.isEmpty ? "Sin nombre" : gitName) <\(gitEmail.isEmpty ? "sin email" : gitEmail)>"
    }

    static let empty = DevSnapshot(
        brewPath: "", xcodePath: "", clangVersion: "", swiftVersion: "", gitVersion: "",
        gitName: "", gitEmail: "", ghStatus: "No verificado", ghAuthenticated: false,
        hasSSHKey: false, sshDetail: "No verificado", sshGitHubStatus: "No probado",
        pathDetail: "", pathOK: false, nodeVersion: "", pythonVersion: "", rustVersion: "",
        javaVersion: "", fishPath: "", currentShell: "", ohMyPoshVersion: "", brewfilePath: "~/Brewfile",
        hasDotfilesDirectory: false, dotfilesStatus: "No verificado"
    )

    static func capture() async -> DevSnapshot {
        async let brew = checked("command -v brew")
        async let xcode = checked("xcode-select -p 2>/dev/null")
        async let clang = checked("clang --version | head -1")
        async let swift = checked("swift --version | head -1")
        async let git = checked("git --version")
        async let name = checked("git config --global user.name")
        async let email = checked("git config --global user.email")
        async let gh = checked("gh auth status 2>&1")
        async let ssh = checked("ls -1 \"$HOME/.ssh\"/*.pub 2>/dev/null | sed 's#'$HOME'/##' | tr '\\n' ', ' | sed 's/, $//'")
        async let sshGitHub = checked("ssh -o BatchMode=yes -T git@github.com 2>&1 || true")
        async let path = checked("printf '%s' \"$PATH\"")
        async let node = checked("node --version")
        async let python = checked("python3 --version")
        async let rust = checked("rustc --version")
        async let java = checked("java -version 2>&1 | head -1")
        async let fish = checked("command -v fish")
        async let shell = checked("printf '%s' \"$SHELL\"")
        async let omp = checked("oh-my-posh --version")
        async let brewfile = checked("[ -f \"$HOME/Brewfile\" ] && echo \"$HOME/Brewfile\" || echo \"No existe ~/Brewfile\"")
        async let dotfiles = checked("""
        if [ -d "$HOME/.dotfiles/.git" ]; then echo "Repo Git listo en ~/.dotfiles"
        elif [ -d "$HOME/.dotfiles" ]; then echo "Carpeta local sin Git en ~/.dotfiles"
        else echo "No existe ~/.dotfiles"
        fi
        """)

        let ghOutput = await gh
        let sshFiles = await ssh
        let pathValue = await path
        let pathParts = pathValue.split(separator: ":").map(String.init)
        let optIndex = pathParts.firstIndex(of: "/opt/homebrew/bin") ?? Int.max
        let usrIndex = pathParts.firstIndex(of: "/usr/bin") ?? Int.max
        let pathOK = optIndex < usrIndex

        return DevSnapshot(
            brewPath: await brew,
            xcodePath: await xcode,
            clangVersion: await clang,
            swiftVersion: await swift,
            gitVersion: await git,
            gitName: await name,
            gitEmail: await email,
            ghStatus: ghOutput.isEmpty ? "gh no autenticado o no instalado" : ghOutput.components(separatedBy: "\n").first ?? ghOutput,
            ghAuthenticated: ghOutput.contains("Logged in") || ghOutput.contains("✓ Logged in") || ghOutput.contains("Active account"),
            hasSSHKey: !sshFiles.isEmpty,
            sshDetail: sshFiles.isEmpty ? "No hay public keys" : sshFiles,
            sshGitHubStatus: (await sshGitHub).components(separatedBy: "\n").first ?? "No probado",
            pathDetail: pathOK ? "/opt/homebrew/bin antes que /usr/bin" : "Revisa orden de PATH",
            pathOK: pathOK,
            nodeVersion: await node,
            pythonVersion: await python,
            rustVersion: await rust,
            javaVersion: await java,
            fishPath: await fish,
            currentShell: await shell,
            ohMyPoshVersion: await omp,
            brewfilePath: await brewfile,
            hasDotfilesDirectory: await checked("[ -d \"$HOME/.dotfiles\" ] && echo yes || true") == "yes",
            dotfilesStatus: await dotfiles
        )
    }

    private static func checked(_ command: String) async -> String {
        (try? await runShell(executable: "/bin/zsh", args: ["-lc", "\(command) || true"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct HealthTile: View {
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

private struct DevPanel<Content: View>: View {
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

private struct DevInfoRow: View {
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

private struct DevActionButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
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

// `shellQuoted` lives in ScriptRunner.swift as a module-internal extension.

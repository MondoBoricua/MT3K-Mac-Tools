import Foundation

enum InstallMethod: Hashable {
    case brewCask(String)
    case brewFormula(String)
    case brewTap(String)
    case npm(String)
    /// Direct .dmg download. Picks the URL matching the host architecture.
    case dmg(arm64: String, x64: String)
    /// Resolves to the latest GitHub release asset matching the given regex
    /// (arm pattern for arm64, intel pattern for x86_64). Downloads + installs the .dmg.
    case githubLatest(repo: String, armPattern: String, intelPattern: String)

    var label: String {
        switch self {
        case .brewCask: return "brew --cask"
        case .brewFormula: return "brew"
        case .brewTap: return "brew tap"
        case .npm: return "npm -g"
        case .dmg: return ".dmg directo"
        case .githubLatest: return "github release"
        }
    }

    var scriptArgs: [String] {
        switch self {
        case .brewCask(let n): return ["cask", n]
        case .brewFormula(let n): return ["formula", n]
        case .brewTap(let p): return ["tap", p]
        case .npm(let p): return ["npm", p]
        case .dmg(let a, let x): return ["dmg", a, x]
        case .githubLatest(let r, let a, let i): return ["github-latest", r, a, i]
        }
    }

    var brewPackageName: String? {
        switch self {
        case .brewCask(let name), .brewFormula(let name), .brewTap(let name):
            return name
        default:
            return nil
        }
    }

    var upgradeScriptArgs: [String]? {
        switch self {
        case .brewCask(let name): return ["upgrade-cask", name]
        case .brewFormula(let name): return ["upgrade-formula", name]
        case .brewTap(let name): return ["upgrade-tap", name]
        default: return nil
        }
    }
}

enum CatalogCategory: String, CaseIterable, Hashable, Identifiable {
    case browsers = "Navegadores"
    case ai = "IA y Coding"
    case dev = "Dev"
    case cybersec = "Ciberseguridad"
    case productivity = "Productividad"
    case design = "Diseño"
    case communication = "Comunicación"
    case cloud = "Cloud y Storage"
    case utilities = "Utilidades"
    case media = "Media"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .browsers: return "safari"
        case .ai: return "sparkles"
        case .dev: return "hammer"
        case .cybersec: return "lock.shield.fill"
        case .productivity: return "checklist"
        case .design: return "paintbrush.pointed.fill"
        case .communication: return "message.fill"
        case .cloud: return "icloud.fill"
        case .utilities: return "wrench.and.screwdriver"
        case .media: return "play.rectangle.on.rectangle"
        }
    }
}

struct CatalogItem: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let symbol: String
    let install: InstallMethod
    let category: CatalogCategory
    /// Filename of the installed .app inside /Applications, when applicable.
    /// Used to detect pre-existing installs and offer a replace prompt.
    var appName: String? = nil
    /// Set true for brewCask items whose payload includes a `.pkg` (e.g. Wireshark,
    /// Zoom, Teams, Cloudflare WARP). Triggers a sudo pre-auth dialog so brew's
    /// internal `sudo installer` can run without a TTY.
    var requiresAdminInstall: Bool = false
}

enum Catalog {
    static let items: [CatalogItem] = [
        // Navegadores
        .init(id: "brave", name: "Brave", description: "Navegador con privacidad por defecto basado en Chromium.",
              symbol: "shield.lefthalf.filled", install: .brewCask("brave-browser"), category: .browsers, appName: "Brave Browser.app"),
        .init(id: "firefox", name: "Firefox", description: "Navegador open source de Mozilla.",
              symbol: "flame.fill", install: .brewCask("firefox"), category: .browsers, appName: "Firefox.app"),
        .init(id: "chrome", name: "Google Chrome", description: "Navegador de Google.",
              symbol: "globe.americas.fill", install: .brewCask("google-chrome"), category: .browsers, appName: "Google Chrome.app"),
        .init(id: "arc", name: "Arc", description: "Navegador con sidebar y spaces de The Browser Company.",
              symbol: "arrow.up.right.circle.fill", install: .brewCask("arc"), category: .browsers, appName: "Arc.app"),
        .init(id: "librewolf", name: "LibreWolf", description: "Fork de Firefox enfocado en privacidad.",
              symbol: "lock.shield.fill", install: .brewCask("librewolf"), category: .browsers, appName: "LibreWolf.app"),
        .init(id: "zen", name: "Zen Browser", description: "Fork de Firefox con UI moderna.",
              symbol: "leaf.fill", install: .brewCask("zen"), category: .browsers, appName: "Zen.app"),
        .init(id: "comet", name: "Comet", description: "Navegador de Perplexity con IA integrada y agent mode.",
              symbol: "sparkle.magnifyingglass", install: .brewCask("comet"), category: .browsers, appName: "Comet.app"),
        .init(id: "chatgpt-atlas", name: "ChatGPT Atlas", description: "Navegador de OpenAI con ChatGPT como copiloto del browsing.",
              symbol: "atom", install: .brewCask("chatgpt-atlas"), category: .browsers, appName: "ChatGPT Atlas.app"),
        .init(id: "opera", name: "Opera", description: "Navegador con VPN, AI assistant y sidebar de redes sociales.",
              symbol: "globe.badge.chevron.backward", install: .brewCask("opera"), category: .browsers, appName: "Opera.app"),
        .init(id: "opera-gx", name: "Opera GX", description: "Opera para gamers: limita CPU/RAM/red, panel Twitch/Discord integrado, modo oscuro intenso.",
              symbol: "gamecontroller.fill", install: .brewCask("opera-gx"), category: .browsers, appName: "Opera GX.app"),

        // IA / Coding
        .init(id: "claude", name: "Claude Desktop", description: "App oficial de Claude de Anthropic.",
              symbol: "brain.head.profile", install: .brewCask("claude"), category: .ai, appName: "Claude.app"),
        .init(id: "codex-desktop", name: "Codex Desktop", description: "App oficial de OpenAI para manejar coding agents (equivalente GUI del CLI).",
              symbol: "command.square.fill", install: .brewCask("codex-app"), category: .ai, appName: "Codex.app"),
        .init(id: "antigravity", name: "Antigravity", description: "Agent orchestration platform de Google Antigravity.",
              symbol: "atom", install: .brewCask("antigravity"), category: .ai, appName: "Antigravity.app"),
        .init(id: "antigravity-cli", name: "Antigravity CLI", description: "Terminal interface para agentes de Google Antigravity.",
              symbol: "terminal.fill", install: .brewCask("antigravity-cli"), category: .ai),
        .init(id: "antigravity-ide", name: "Antigravity IDE Classic", description: "AI Coding Agent IDE clásico de Google Antigravity.",
              symbol: "curlybraces.square.fill", install: .brewCask("antigravity-ide"), category: .ai, appName: "Antigravity IDE.app"),
        .init(id: "opendesign", name: "OpenDesign CLI", description: "CLI para trabajar con archivos .octopus de OpenDesign.",
              symbol: "doc.text.magnifyingglass", install: .npm("opendesign"), category: .ai),
        .init(id: "pencil-cli", name: "Pencil CLI", description: "CLI de pencil.dev — diseño dentro del IDE con IA.",
              symbol: "pencil.tip.crop.circle", install: .npm("@pencil.dev/cli"), category: .ai),
        .init(id: "claude-code", name: "Claude Code", description: "CLI oficial de Anthropic para coding agéntico. Binario nativo via brew (sin Node).",
              symbol: "terminal.fill", install: .brewCask("claude-code"), category: .ai),
        .init(id: "codex-cli", name: "Codex CLI", description: "CLI oficial de OpenAI para coding con GPT. Self-contained vía brew, sin Node.",
              symbol: "command.square", install: .brewCask("codex"), category: .ai),
        .init(id: "opencode", name: "opencode", description: "Coding agent open source en terminal.",
              symbol: "chevron.left.forwardslash.chevron.right", install: .brewFormula("opencode"), category: .ai),
        .init(id: "cursor", name: "Cursor", description: "Editor con IA basado en VSCode.",
              symbol: "cursorarrow.click.2", install: .brewCask("cursor"), category: .ai, appName: "Cursor.app"),
        .init(id: "windsurf", name: "Windsurf", description: "IDE con IA de Codeium — Cascade agent + chat + autocomplete.",
              symbol: "wind", install: .brewCask("windsurf"), category: .ai, appName: "Windsurf.app"),
        .init(id: "zed", name: "Zed", description: "Editor moderno multiplayer escrito en Rust.",
              symbol: "bolt.fill", install: .brewCask("zed"), category: .ai, appName: "Zed.app"),
        .init(id: "ollama", name: "Ollama", description: "Corre LLMs locales (Llama, Mistral, etc).",
              symbol: "cpu.fill", install: .brewCask("ollama-app"), category: .ai, appName: "Ollama.app"),
        .init(id: "lmstudio", name: "LM Studio", description: "GUI para correr LLMs locales con UI tipo ChatGPT (alternativa visual a Ollama).",
              symbol: "shippingbox.fill", install: .brewCask("lm-studio"), category: .ai, appName: "LM Studio.app"),
        .init(id: "ollamac", name: "Ollamac", description: "GUI alternativa para Ollama — chat estilo Mac nativo (community).",
              symbol: "bubble.left.and.text.bubble.right.fill", install: .brewCask("ollamac"), category: .ai, appName: "Ollamac.app"),
        .init(id: "anythingllm", name: "AnythingLLM", description: "Chat con tus documentos usando LLMs locales o cloud. RAG + workspaces.",
              symbol: "doc.text.below.ecg", install: .brewCask("anythingllm"), category: .ai, appName: "AnythingLLM.app"),
        .init(id: "pinokio", name: "Pinokio", description: "Launcher para correr modelos de IA y scripts AI en local con UI.",
              symbol: "play.square.stack.fill", install: .githubLatest(
                repo: "pinokiocomputer/pinokio",
                armPattern: "arm64\\.dmg$",
                intelPattern: "Pinokio-[0-9.]+\\.dmg$"
              ), category: .ai, appName: "Pinokio.app"),
        .init(id: "chatgpt", name: "ChatGPT", description: "App oficial de OpenAI para chatear con GPT.",
              symbol: "bubble.left.and.bubble.right.fill", install: .brewCask("chatgpt"), category: .ai, appName: "ChatGPT.app"),
        .init(id: "gemini-app", name: "Gemini", description: "App oficial de Google para Gemini AI.",
              symbol: "sparkles", install: .brewCask("google-gemini"), category: .ai, appName: "Gemini.app"),
        .init(id: "gemini-cli", name: "Gemini CLI", description: "CLI oficial de Google para Gemini con coding agent.",
              symbol: "sparkle", install: .brewFormula("gemini-cli"), category: .ai),
        .init(id: "qwen-code", name: "Qwen Code", description: "CLI de coding de Alibaba (Qwen models).",
              symbol: "chevron.left.forwardslash.chevron.right", install: .brewFormula("qwen-code"), category: .ai),
        .init(id: "kimi-cli", name: "Kimi CLI", description: "CLI de IA para trabajar con modelos Kimi desde terminal.",
              symbol: "sparkle.magnifyingglass", install: .brewFormula("kimi-cli"), category: .ai),

        // Dev
        .init(id: "vscode", name: "Visual Studio Code", description: "Editor de Microsoft.",
              symbol: "chevron.left.slash.chevron.right", install: .brewCask("visual-studio-code"), category: .dev, appName: "Visual Studio Code.app"),
        .init(id: "iterm2", name: "iTerm2", description: "Terminal alternativa para macOS.",
              symbol: "apple.terminal.fill", install: .brewCask("iterm2"), category: .dev, appName: "iTerm.app"),
        .init(id: "ghostty", name: "Ghostty", description: "Terminal moderno, rápido, GPU-accelerated.",
              symbol: "rectangle.dashed", install: .brewCask("ghostty"), category: .dev, appName: "Ghostty.app"),
        .init(id: "warp", name: "Warp", description: "Terminal con IA y bloques.",
              symbol: "rectangle.split.3x1.fill", install: .brewCask("warp"), category: .dev, appName: "Warp.app"),
        .init(id: "orbstack", name: "OrbStack", description: "Docker + Linux VMs livianas para Mac.",
              symbol: "shippingbox.fill", install: .brewCask("orbstack"), category: .dev, appName: "OrbStack.app"),
        .init(id: "android-studio", name: "Android Studio", description: "IDE oficial de Google para desarrollo Android.",
              symbol: "apps.iphone", install: .brewCask("android-studio"), category: .dev, appName: "Android Studio.app"),
        .init(id: "github", name: "GitHub Desktop", description: "Cliente GUI oficial de GitHub.",
              symbol: "externaldrive.fill.badge.checkmark", install: .brewCask("github"), category: .dev, appName: "GitHub Desktop.app"),
        .init(id: "node", name: "Node.js", description: "Runtime de JavaScript (necesario para npm).",
              symbol: "circle.hexagongrid.fill", install: .brewFormula("node"), category: .dev),
        .init(id: "git", name: "Git (Homebrew)", description: "Instala la versión actual de Git gestionada por Brew. macOS ya trae una versión del sistema.",
              symbol: "arrow.triangle.branch", install: .brewFormula("git"), category: .dev),
        .init(id: "gh", name: "GitHub CLI", description: "CLI oficial de GitHub.",
              symbol: "terminal", install: .brewFormula("gh"), category: .dev),
        .init(id: "tailwindcss", name: "Tailwind CSS", description: "CLI standalone de Tailwind CSS v4 (sin Node — binary nativo).",
              symbol: "paintbrush.fill", install: .brewFormula("tailwindcss"), category: .dev),
        .init(id: "kitty", name: "Kitty", description: "Terminal GPU-accelerated, extensible y rápida.",
              symbol: "cat.fill", install: .brewCask("kitty"), category: .dev, appName: "kitty.app"),
        .init(id: "fish", name: "Fish Shell", description: "Shell amigable con autosuggestions y syntax highlighting.",
              symbol: "fish.fill", install: .brewFormula("fish"), category: .dev),
        .init(id: "tmux", name: "tmux", description: "Multiplexor de terminal — sesiones persistentes, splits, windows.",
              symbol: "square.split.2x2.fill", install: .brewFormula("tmux"), category: .dev),
        .init(id: "fzf", name: "fzf", description: "Fuzzy finder en línea de comandos — ideal para menús interactivos en alias y scripts.",
              symbol: "magnifyingglass.circle.fill", install: .brewFormula("fzf"), category: .dev),
        .init(id: "oh-my-posh", name: "Oh My Posh", description: "Prompt theme engine para shells modernos.",
              symbol: "paintpalette.fill", install: .brewFormula("oh-my-posh"), category: .dev),
        .init(id: "flutter", name: "Flutter", description: "SDK de Google para apps multiplataforma.",
              symbol: "diamond.fill", install: .brewCask("flutter"), category: .dev),
        .init(id: "temurin", name: "Temurin JDK", description: "Distribución OpenJDK de Eclipse Adoptium.",
              symbol: "cup.and.saucer.fill", install: .brewCask("temurin"), category: .dev, requiresAdminInstall: true),
        .init(id: "openjdk17", name: "OpenJDK 17", description: "JDK 17 para toolchains que requieren una versión LTS específica.",
              symbol: "cup.and.saucer", install: .brewFormula("openjdk@17"), category: .dev),
        .init(id: "cmake", name: "CMake", description: "Sistema de build multiplataforma para proyectos C/C++.",
              symbol: "hammer.circle.fill", install: .brewFormula("cmake"), category: .dev),
        .init(id: "ninja", name: "Ninja", description: "Build system pequeño y rápido usado por CMake y toolchains nativos.",
              symbol: "bolt.horizontal.fill", install: .brewFormula("ninja"), category: .dev),
        .init(id: "rust", name: "Rust", description: "Toolchain del lenguaje Rust.",
              symbol: "gearshape.fill", install: .brewFormula("rust"), category: .dev),
        .init(id: "python313", name: "Python 3.13", description: "Runtime Python moderno gestionado por Homebrew.",
              symbol: "chevron.left.forwardslash.chevron.right", install: .brewFormula("python@3.13"), category: .dev),
        .init(id: "pnpm", name: "pnpm", description: "Package manager rápido y eficiente para JavaScript.",
              symbol: "shippingbox.circle.fill", install: .brewFormula("pnpm"), category: .dev),
        .init(id: "yarn", name: "Yarn", description: "Package manager para proyectos JavaScript.",
              symbol: "shippingbox.circle", install: .brewFormula("yarn"), category: .dev),
        .init(id: "docker-cli", name: "Docker CLI", description: "Cliente de Docker en línea de comando.",
              symbol: "terminal.fill", install: .brewFormula("docker"), category: .dev),
        .init(id: "colima", name: "Colima", description: "Contenedores Docker y Kubernetes sobre Lima para macOS.",
              symbol: "cube.box.fill", install: .brewFormula("colima"), category: .dev),
        .init(id: "composer", name: "Composer", description: "Dependency manager para PHP.",
              symbol: "curlybraces.square.fill", install: .brewFormula("composer"), category: .dev),
        .init(id: "cocoapods", name: "CocoaPods", description: "Gestor de dependencias para proyectos iOS/macOS.",
              symbol: "square.stack.3d.up.fill", install: .brewFormula("cocoapods"), category: .dev),
        .init(id: "fastlane", name: "fastlane", description: "Automatización de build, signing y releases móviles.",
              symbol: "paperplane.circle.fill", install: .brewFormula("fastlane"), category: .dev),
        .init(id: "ios-deploy", name: "ios-deploy", description: "Instala y depura apps iOS desde línea de comando.",
              symbol: "iphone.and.arrow.forward", install: .brewFormula("ios-deploy"), category: .dev),
        .init(id: "watchman", name: "Watchman", description: "File watcher de Meta usado por toolchains como React Native.",
              symbol: "eye.fill", install: .brewFormula("watchman"), category: .dev),
        .init(id: "stripe-cli", name: "Stripe CLI", description: "CLI oficial para probar webhooks y recursos de Stripe.",
              symbol: "creditcard.fill", install: .brewFormula("stripe-cli"), category: .dev),
        .init(id: "coreutils", name: "GNU Coreutils", description: "Versiones GNU de utilidades base como ls, cat, sort y date.",
              symbol: "terminal.fill", install: .brewFormula("coreutils"), category: .dev),
        .init(id: "wget", name: "wget", description: "Descargas HTTP/FTP desde terminal.",
              symbol: "arrow.down.doc.fill", install: .brewFormula("wget"), category: .dev),

        // Ciberseguridad
        .init(id: "wireshark", name: "Wireshark", description: "Analizador de protocolos de red — inspecciona tráfico TCP/IP, HTTP, TLS, etc.",
              symbol: "network", install: .brewCask("wireshark-app"), category: .cybersec, appName: "Wireshark.app", requiresAdminInstall: true),
        .init(id: "burp-suite", name: "Burp Suite CE", description: "Proxy interceptor para pentesting web (Community Edition).",
              symbol: "ladybug.fill", install: .brewCask("burp-suite"), category: .cybersec, appName: "Burp Suite Community Edition.app"),
        .init(id: "owasp-zap", name: "OWASP ZAP", description: "Web app scanner y proxy interceptor open source de OWASP.",
              symbol: "bolt.shield.fill", install: .brewCask("zap"), category: .cybersec, appName: "ZAP.app"),
        .init(id: "proxyman", name: "Proxyman", description: "Proxy de debug HTTP/HTTPS nativo para Mac — UI moderna.",
              symbol: "arrow.left.arrow.right.circle.fill", install: .brewCask("proxyman"), category: .cybersec, appName: "Proxyman.app"),
        .init(id: "charles", name: "Charles Proxy", description: "Proxy HTTP/HTTPS clásico para debug de red.",
              symbol: "arrow.triangle.swap", install: .brewCask("charles"), category: .cybersec, appName: "Charles.app"),
        .init(id: "little-snitch", name: "Little Snitch", description: "Firewall de salida — alerta cuando una app intenta conectarse afuera.",
              symbol: "shield.righthalf.filled", install: .brewCask("little-snitch"), category: .cybersec, appName: "Little Snitch.app", requiresAdminInstall: true),
        .init(id: "lulu", name: "LuLu", description: "Firewall de salida open source de Objective-See.",
              symbol: "shield.lefthalf.filled", install: .brewCask("lulu"), category: .cybersec, appName: "LuLu.app", requiresAdminInstall: true),
        .init(id: "knockknock", name: "KnockKnock", description: "Detecta software persistente sospechoso en tu Mac (Objective-See).",
              symbol: "magnifyingglass.circle.fill", install: .brewCask("knockknock"), category: .cybersec, appName: "KnockKnock.app"),
        // CLIs de pentesting (Kali-style)
        .init(id: "nmap", name: "nmap", description: "Scanner de red y de puertos — el clásico.",
              symbol: "scope", install: .brewFormula("nmap"), category: .cybersec),
        .init(id: "masscan", name: "masscan", description: "Scanner de puertos masivo (millones de IPs/seg).",
              symbol: "scope", install: .brewFormula("masscan"), category: .cybersec),
        .init(id: "tcpdump", name: "tcpdump", description: "Captura de paquetes en línea de comando (alternativa CLI a Wireshark).",
              symbol: "antenna.radiowaves.left.and.right", install: .brewFormula("tcpdump"), category: .cybersec),
        .init(id: "hashcat", name: "hashcat", description: "Recuperador de passwords por GPU — el más rápido del mercado.",
              symbol: "lock.open.trianglebadge.exclamationmark", install: .brewFormula("hashcat"), category: .cybersec),
        .init(id: "john", name: "John the Ripper", description: "Cracker de passwords clásico.",
              symbol: "key.viewfinder", install: .brewFormula("john"), category: .cybersec),
        .init(id: "hydra", name: "Hydra", description: "Brute-force de logins en muchos protocolos (SSH, FTP, HTTP, etc.).",
              symbol: "lock.rotation", install: .brewFormula("hydra"), category: .cybersec),
        .init(id: "sqlmap", name: "sqlmap", description: "Detección y explotación automatizada de SQL injection.",
              symbol: "cylinder.fill", install: .brewFormula("sqlmap"), category: .cybersec),
        .init(id: "nikto", name: "nikto", description: "Scanner de vulnerabilidades web clásico.",
              symbol: "doc.text.magnifyingglass", install: .brewFormula("nikto"), category: .cybersec),
        .init(id: "ffuf", name: "ffuf", description: "Fuzzer web rápido en Go (directorios, parámetros, vhosts).",
              symbol: "circle.grid.cross.fill", install: .brewFormula("ffuf"), category: .cybersec),
        .init(id: "gobuster", name: "gobuster", description: "Brute-forcer de directorios y subdominios.",
              symbol: "folder.badge.questionmark", install: .brewFormula("gobuster"), category: .cybersec),
        .init(id: "aircrack-ng", name: "aircrack-ng", description: "Suite de auditoría de WiFi (WEP/WPA cracking).",
              symbol: "wifi.exclamationmark", install: .brewFormula("aircrack-ng"), category: .cybersec),
        .init(id: "sslscan", name: "sslscan", description: "Auditor de configuración SSL/TLS de servidores.",
              symbol: "lock.shield", install: .brewFormula("sslscan"), category: .cybersec),
        .init(id: "testssl", name: "testssl.sh", description: "Test exhaustivo de SSL/TLS — cifras, vulns, certificados.",
              symbol: "lock.doc.fill", install: .brewFormula("testssl"), category: .cybersec),
        .init(id: "cloudflared", name: "cloudflared", description: "Cliente CLI para Cloudflare Tunnel.",
              symbol: "cloud.fill", install: .brewFormula("cloudflared"), category: .cybersec),
        .init(id: "wireguard-tools", name: "WireGuard Tools", description: "Herramientas CLI para WireGuard VPN.",
              symbol: "lock.shield.fill", install: .brewFormula("wireguard-tools"), category: .cybersec),

        // Productividad
        .init(id: "notion", name: "Notion", description: "Notas, wikis, bases de datos y docs.",
              symbol: "doc.text.fill", install: .brewCask("notion"), category: .productivity, appName: "Notion.app"),
        .init(id: "obsidian", name: "Obsidian", description: "Notas en markdown locales con linking bidireccional.",
              symbol: "circle.hexagongrid.circle.fill", install: .brewCask("obsidian"), category: .productivity, appName: "Obsidian.app"),
        .init(id: "linear", name: "Linear", description: "Tracker de issues y proyectos para equipos.",
              symbol: "arrow.up.right.square.fill", install: .brewCask("linear"), category: .productivity, appName: "Linear.app"),
        .init(id: "logseq", name: "Logseq", description: "Outliner de notas open source con graph view.",
              symbol: "list.bullet.indent", install: .brewCask("logseq"), category: .productivity, appName: "Logseq.app"),
        .init(id: "notion-calendar", name: "Notion Calendar", description: "Calendar app de Notion (ex Cron).",
              symbol: "calendar", install: .brewCask("notion-calendar"), category: .productivity, appName: "Notion Calendar.app"),
        .init(id: "craft", name: "Craft", description: "Editor de documentos rich con blocks y AI.",
              symbol: "doc.richtext.fill", install: .brewCask("craft"), category: .productivity, appName: "Craft.app"),
        .init(id: "wispr-flow", name: "Wispr Flow", description: "Dictado por voz con IA para escribir más rápido en cualquier app.",
              symbol: "mic.fill", install: .brewCask("wispr-flow"), category: .productivity, appName: "Wispr Flow.app"),
        .init(id: "handy", name: "Handy", description: "Speech-to-text liviano para dictar y transcribir desde el Mac.",
              symbol: "waveform.and.mic", install: .brewCask("handy"), category: .productivity, appName: "Handy.app"),
        .init(id: "mas", name: "mas", description: "CLI para instalar y actualizar apps del Mac App Store.",
              symbol: "bag.fill", install: .brewFormula("mas"), category: .productivity),
        .init(id: "cleanshot", name: "CleanShot X", description: "Capturas, grabación de pantalla y anotaciones rápidas.",
              symbol: "camera.viewfinder", install: .brewCask("cleanshot"), category: .productivity, appName: "CleanShot X.app"),

        // Diseño
        .init(id: "figma", name: "Figma", description: "Diseño de interfaces colaborativo.",
              symbol: "rectangle.3.group.fill", install: .brewCask("figma"), category: .design, appName: "Figma.app"),
        .init(id: "sketch", name: "Sketch", description: "Diseño vectorial de UI clásico para Mac.",
              symbol: "scribble.variable", install: .brewCask("sketch"), category: .design, appName: "Sketch.app"),
        .init(id: "affinity-designer", name: "Affinity Designer 2", description: "Diseño vectorial e ilustración pro (alternativa a Illustrator).",
              symbol: "pencil.and.outline", install: .brewCask("affinity-designer"), category: .design, appName: "Affinity Designer 2.app"),
        .init(id: "affinity-photo", name: "Affinity Photo 2", description: "Edición fotográfica pro (alternativa a Photoshop).",
              symbol: "camera.macro", install: .brewCask("affinity-photo"), category: .design, appName: "Affinity Photo 2.app"),
        .init(id: "affinity-publisher", name: "Affinity Publisher 2", description: "Maquetación editorial pro (alternativa a InDesign).",
              symbol: "doc.richtext", install: .brewCask("affinity-publisher"), category: .design, appName: "Affinity Publisher 2.app"),
        .init(id: "blender", name: "Blender", description: "3D modeling, animación y rendering open source.",
              symbol: "cube.transparent.fill", install: .brewCask("blender"), category: .design, appName: "Blender.app"),
        .init(id: "krita", name: "Krita", description: "Pintura digital open source — alternativa a Photoshop/Procreate.",
              symbol: "paintbrush.pointed", install: .brewCask("krita"), category: .design, appName: "krita.app"),
        .init(id: "inkscape", name: "Inkscape", description: "Editor vectorial open source para SVG e ilustración.",
              symbol: "pencil.and.outline", install: .brewCask("inkscape"), category: .design, appName: "Inkscape.app"),
        .init(id: "image2icon", name: "Image2Icon", description: "Convierte imágenes en iconos de macOS.",
              symbol: "app.badge.fill", install: .brewCask("image2icon"), category: .design, appName: "Image2Icon.app"),
        .init(id: "imagemagick", name: "ImageMagick", description: "CLI para convertir, optimizar y manipular imágenes.",
              symbol: "photo.stack.fill", install: .brewFormula("imagemagick"), category: .design),
        .init(id: "hack-nerd-font", name: "Hack Nerd Font", description: "Fuente Nerd Font para terminales y editores.",
              symbol: "textformat", install: .brewCask("font-hack-nerd-font"), category: .design),
        .init(id: "meslo-nerd-font", name: "Meslo LG Nerd Font", description: "Fuente popular para prompts de terminal con iconos.",
              symbol: "textformat.alt", install: .brewCask("font-meslo-lg-nerd-font"), category: .design),
        .init(id: "roboto-slab", name: "Roboto Slab", description: "Fuente slab serif de Google Fonts.",
              symbol: "character.cursor.ibeam", install: .brewCask("font-roboto-slab"), category: .design),
        .init(id: "pencil-app", name: "Pencil Desktop", description: "App de pencil.dev — diseño asistido por IA. Descarga directa del .dmg.",
              symbol: "pencil.tip", install: .dmg(
                arm64: "https://www.pencil.dev/download/Pencil-mac-arm64.dmg",
                x64: "https://www.pencil.dev/download/Pencil-mac-x64.dmg"
              ), category: .design, appName: "Pencil.app"),

        // Comunicación
        .init(id: "whatsapp", name: "WhatsApp", description: "Cliente oficial de WhatsApp.",
              symbol: "phone.bubble.fill", install: .brewCask("whatsapp"), category: .communication, appName: "WhatsApp.app"),
        .init(id: "telegram", name: "Telegram Desktop", description: "Cliente Qt de Telegram (más estable que el nativo Swift).",
              symbol: "paperplane.fill", install: .brewCask("telegram-desktop"), category: .communication, appName: "Telegram Desktop.app"),
        .init(id: "discord", name: "Discord", description: "Chat y voz para comunidades.",
              symbol: "gamecontroller.fill", install: .brewCask("discord"), category: .communication, appName: "Discord.app"),
        .init(id: "slack", name: "Slack", description: "Chat de equipos de trabajo.",
              symbol: "number.square.fill", install: .brewCask("slack"), category: .communication, appName: "Slack.app"),
        .init(id: "signal", name: "Signal", description: "Mensajería encriptada end-to-end.",
              symbol: "lock.fill", install: .brewCask("signal"), category: .communication, appName: "Signal.app"),
        .init(id: "messenger", name: "Messenger", description: "Cliente oficial de Facebook Messenger.",
              symbol: "bubble.left.fill", install: .brewCask("messenger"), category: .communication, appName: "Messenger.app"),
        .init(id: "zoom", name: "Zoom", description: "Videoconferencias.",
              symbol: "video.fill", install: .brewCask("zoom"), category: .communication, appName: "zoom.us.app", requiresAdminInstall: true),
        .init(id: "microsoft-teams", name: "Microsoft Teams", description: "Chat y videollamadas de Microsoft.",
              symbol: "person.2.fill", install: .brewCask("microsoft-teams"), category: .communication, appName: "Microsoft Teams.app", requiresAdminInstall: true),
        .init(id: "element", name: "Element", description: "Cliente para la red Matrix (chat descentralizado).",
              symbol: "checkmark.shield.fill", install: .brewCask("element"), category: .communication, appName: "Element.app"),
        .init(id: "mattermost", name: "Mattermost", description: "Chat de equipos open source.",
              symbol: "bubble.middle.bottom.fill", install: .brewCask("mattermost"), category: .communication, appName: "Mattermost.app"),
        .init(id: "anydesk", name: "AnyDesk", description: "Acceso remoto multiplataforma para soporte y administración.",
              symbol: "display.and.arrow.down", install: .brewCask("anydesk"), category: .communication, appName: "AnyDesk.app"),
        .init(id: "rustdesk", name: "RustDesk", description: "Acceso remoto open source y multiplataforma.",
              symbol: "display.trianglebadge.exclamationmark", install: .brewCask("rustdesk"), category: .communication, appName: "RustDesk.app"),
        .init(id: "localsend", name: "LocalSend", description: "Comparte archivos en red local entre dispositivos sin nube.",
              symbol: "arrow.left.arrow.right.circle.fill", install: .brewCask("localsend"), category: .communication, appName: "LocalSend.app"),
        .init(id: "tiger-vnc", name: "TigerVNC", description: "Cliente y servidor VNC open source para escritorio remoto.",
              symbol: "display.2", install: .brewFormula("tiger-vnc"), category: .communication),

        // Utilidades
        .init(id: "raycast", name: "Raycast", description: "Spotlight con esteroides + extensiones.",
              symbol: "command.circle.fill", install: .brewCask("raycast"), category: .utilities, appName: "Raycast.app"),
        .init(id: "rectangle", name: "Rectangle", description: "Window snapping al estilo Windows/Linux.",
              symbol: "rectangle.split.2x1.fill", install: .brewCask("rectangle"), category: .utilities, appName: "Rectangle.app"),
        .init(id: "stats", name: "Stats", description: "Monitor de CPU/RAM/red en menu bar.",
              symbol: "chart.line.uptrend.xyaxis", install: .brewCask("stats"), category: .utilities, appName: "Stats.app"),
        .init(id: "betterdisplay", name: "BetterDisplay", description: "Control avanzado de monitores, HiDPI, brillo y virtual displays.",
              symbol: "display", install: .brewCask("betterdisplay"), category: .utilities, appName: "BetterDisplay.app"),
        .init(id: "latest", name: "Latest", description: "Muestra updates disponibles para apps instaladas fuera de la App Store.",
              symbol: "arrow.down.circle.fill", install: .brewCask("latest"), category: .utilities, appName: "Latest.app"),
        .init(id: "aldente", name: "AlDente", description: "Limita la carga de batería para cuidar la salud del MacBook.",
              symbol: "battery.75percent", install: .brewCask("aldente"), category: .utilities, appName: "AlDente.app"),
        .init(id: "caffeine", name: "Caffeine", description: "Evita que el Mac entre en sleep desde la menu bar.",
              symbol: "cup.and.saucer.fill", install: .brewCask("caffeine"), category: .utilities, appName: "Caffeine.app"),
        .init(id: "jordanbaird-ice", name: "Ice", description: "Oculta, organiza y limpia iconos de la menu bar.",
              symbol: "menubar.rectangle", install: .brewCask("jordanbaird-ice"), category: .utilities, appName: "Ice.app"),
        .init(id: "keka", name: "Keka", description: "Compresor/descompresor moderno para 7z, zip, rar, tar, dmg y más.",
              symbol: "archivebox.fill", install: .brewCask("keka"), category: .utilities, appName: "Keka.app"),
        .init(id: "balenaetcher", name: "balenaEtcher", description: "Flashea imágenes ISO/IMG a USB y tarjetas SD.",
              symbol: "externaldrive.badge.plus", install: .brewCask("balenaetcher"), category: .utilities, appName: "balenaEtcher.app"),
        .init(id: "impactor", name: "Impactor", description: "Herramienta para instalar y gestionar paquetes en dispositivos.",
              symbol: "hammer.circle.fill", install: .brewCask("impactor"), category: .utilities, appName: "Impactor.app"),
        .init(id: "appcleaner", name: "AppCleaner", description: "Desinstala apps con todos sus residuos.",
              symbol: "trash.fill", install: .brewCask("appcleaner"), category: .utilities, appName: "AppCleaner.app"),
        .init(id: "the-unarchiver", name: "The Unarchiver", description: "Descompresor universal (rar, 7z, etc).",
              symbol: "archivebox.fill", install: .brewCask("the-unarchiver"), category: .utilities, appName: "The Unarchiver.app"),
        .init(id: "1password", name: "1Password", description: "Gestor de contraseñas.",
              symbol: "key.fill", install: .brewCask("1password"), category: .utilities, appName: "1Password.app"),
        .init(id: "bitwarden", name: "Bitwarden", description: "Gestor de contraseñas open source.",
              symbol: "lock.rectangle.fill", install: .brewCask("bitwarden"), category: .utilities, appName: "Bitwarden.app"),
        .init(id: "cloudflare-warp", name: "Cloudflare WARP", description: "VPN/DNS de Cloudflare — mejora privacy y a veces velocidad de red.",
              symbol: "shield.checkered", install: .brewCask("cloudflare-warp"), category: .utilities, appName: "Cloudflare WARP.app", requiresAdminInstall: true),
        .init(id: "surfshark", name: "Surfshark", description: "VPN comercial — multi-hop, kill switch, sin límite de dispositivos.",
              symbol: "lock.shield.fill", install: .brewCask("surfshark"), category: .utilities, appName: "Surfshark.app"),
        .init(id: "windows-app", name: "Windows App", description: "Cliente oficial de Microsoft para conectarte a Windows, Cloud PCs y escritorios remotos.",
              symbol: "display.and.arrow.down", install: .brewCask("windows-app"), category: .utilities, appName: "Windows App.app", requiresAdminInstall: true),
        .init(id: "tailscale", name: "Tailscale", description: "VPN mesh privada basada en WireGuard para conectar tus dispositivos.",
              symbol: "point.3.connected.trianglepath.dotted", install: .brewCask("tailscale-app"), category: .utilities, appName: "Tailscale.app", requiresAdminInstall: true),
        .init(id: "btop", name: "btop", description: "Monitor de recursos en terminal con UI interactiva.",
              symbol: "chart.bar.xaxis", install: .brewFormula("btop"), category: .utilities),
        .init(id: "asitop", name: "asitop", description: "Dashboard estilo htop para Apple Silicon: CPU + GPU + ANE + potencia. Ejecuta con sudo asitop.",
              symbol: "cpu.fill", install: .brewFormula("asitop"), category: .utilities),
        .init(id: "mactop", name: "mactop", description: "Monitor para Apple Silicon (CPU/GPU/RAM por núcleo). Alternativa a asitop. Ejecuta con sudo mactop.",
              symbol: "gauge.with.dots.needle.bottom.50percent", install: .brewFormula("mactop"), category: .utilities),
        .init(id: "fastfetch", name: "fastfetch", description: "Resumen rápido del sistema en terminal.",
              symbol: "speedometer", install: .brewFormula("fastfetch"), category: .utilities),
        .init(id: "lsd", name: "lsd", description: "Reemplazo moderno de ls con iconos y colores.",
              symbol: "folder.fill", install: .brewFormula("lsd"), category: .utilities),
        .init(id: "yazi", name: "Yazi", description: "File manager de terminal rápido y moderno.",
              symbol: "folder.badge.gearshape", install: .brewFormula("yazi"), category: .utilities),
        .init(id: "duti", name: "duti", description: "Configura asociaciones de archivos y apps por defecto desde terminal.",
              symbol: "doc.badge.gearshape", install: .brewFormula("duti"), category: .utilities),
        .init(id: "speedtest", name: "Speedtest CLI", description: "Prueba velocidad de internet desde terminal.",
              symbol: "gauge.with.dots.needle.67percent", install: .brewTap("teamookla/speedtest/speedtest"), category: .utilities),
        .init(id: "flock", name: "flock", description: "Bloqueos de archivos para scripts y automatizaciones.",
              symbol: "lock.square.fill", install: .brewFormula("flock"), category: .utilities),
        .init(id: "cava", name: "CAVA", description: "Visualizador de audio en terminal.",
              symbol: "waveform", install: .brewFormula("cava"), category: .utilities),
        .init(id: "cbonsai", name: "cbonsai", description: "Genera bonsais ASCII animados en terminal.",
              symbol: "leaf.fill", install: .brewFormula("cbonsai"), category: .utilities),
        .init(id: "cmatrix", name: "cmatrix", description: "Animación estilo Matrix para terminal.",
              symbol: "rectangle.and.text.magnifyingglass", install: .brewFormula("cmatrix"), category: .utilities),
        .init(id: "genact", name: "genact", description: "Simulador de actividad falsa en terminal.",
              symbol: "terminal", install: .brewFormula("genact"), category: .utilities),
        .init(id: "pipes-sh", name: "pipes.sh", description: "Pipes animados como screensaver de terminal.",
              symbol: "pipe.and.drop", install: .brewFormula("pipes-sh"), category: .utilities),
        .init(id: "tty-clock", name: "tty-clock", description: "Reloj digital grande para terminal.",
              symbol: "clock.fill", install: .brewFormula("tty-clock"), category: .utilities),

        // Productividad adicional
        .init(id: "libreoffice", name: "LibreOffice", description: "Suite office libre compatible con documentos, hojas de cálculo y presentaciones.",
              symbol: "doc.on.doc.fill", install: .brewCask("libreoffice"), category: .productivity, appName: "LibreOffice.app"),

        // Cloud y Storage
        .init(id: "dropbox", name: "Dropbox", description: "Sincronización de archivos en la nube.",
              symbol: "shippingbox.and.arrow.backward.fill", install: .brewCask("dropbox"), category: .cloud, appName: "Dropbox.app"),
        .init(id: "google-drive", name: "Google Drive", description: "Cliente de Google Drive para macOS.",
              symbol: "icloud.and.arrow.up.fill", install: .brewCask("google-drive"), category: .cloud, appName: "Google Drive.app", requiresAdminInstall: true),
        .init(id: "onedrive", name: "OneDrive", description: "Cliente de OneDrive (Microsoft 365).",
              symbol: "cloud.fill", install: .brewCask("onedrive"), category: .cloud, appName: "OneDrive.app", requiresAdminInstall: true),
        .init(id: "megasync", name: "MEGAsync", description: "Cliente de sincronización de MEGA.",
              symbol: "externaldrive.fill.badge.icloud", install: .brewCask("megasync"), category: .cloud, appName: "MEGAsync.app"),

        // Media
        .init(id: "vlc", name: "VLC", description: "Reproductor universal de video.",
              symbol: "play.tv.fill", install: .brewCask("vlc"), category: .media, appName: "VLC.app"),
        .init(id: "iina", name: "IINA", description: "Reproductor de video nativo para macOS.",
              symbol: "play.rectangle.fill", install: .brewCask("iina"), category: .media, appName: "IINA.app"),
        .init(id: "moonlight", name: "Moonlight", description: "Cliente GameStream para jugar por streaming desde una PC con NVIDIA/Sunshine.",
              symbol: "moon.stars.fill", install: .brewCask("moonlight"), category: .media, appName: "Moonlight.app"),
        .init(id: "spotify", name: "Spotify", description: "Streaming de música.",
              symbol: "music.note", install: .brewCask("spotify"), category: .media, appName: "Spotify.app"),
        .init(id: "pear-desktop", name: "Pear Desktop", description: "Cliente ad-free para YouTube Music con extensiones y app nativa.",
              symbol: "music.quarternote.3", install: .brewTap("pear-devs/pear/pear-desktop"), category: .media, appName: "Pear Desktop.app"),
        .init(id: "obs", name: "OBS Studio", description: "Streaming y grabación de video.",
              symbol: "dot.radiowaves.left.and.right", install: .brewCask("obs"), category: .media, appName: "OBS.app"),
        .init(id: "geforce-now", name: "GeForce Now", description: "Cloud gaming de NVIDIA — corre juegos AAA desde la nube.",
              symbol: "gamecontroller.fill", install: .brewCask("nvidia-geforce-now"), category: .media, appName: "GeForceNOW.app"),
        .init(id: "steam", name: "Steam", description: "Tienda y launcher de juegos de Valve.",
              symbol: "gamecontroller.fill", install: .brewCask("steam"), category: .media, appName: "Steam.app"),
        .init(id: "virtual-desktop-streamer", name: "Virtual Desktop Streamer", description: "Streaming VR/desktop desde Mac o PC hacia headsets compatibles.",
              symbol: "visionpro.fill", install: .brewCask("virtual-desktop-streamer"), category: .media, appName: "Virtual Desktop Streamer.app", requiresAdminInstall: true),
        .init(id: "blackhole-2ch", name: "BlackHole 2ch", description: "Driver virtual de audio de 2 canales para ruteo interno.",
              symbol: "speaker.wave.2.fill", install: .brewCask("blackhole-2ch"), category: .media, requiresAdminInstall: true),
        .init(id: "mpv", name: "mpv", description: "Reproductor multimedia CLI potente y scriptable.",
              symbol: "play.circle.fill", install: .brewFormula("mpv"), category: .media),
        .init(id: "scrcpy", name: "scrcpy", description: "Controla y refleja Android desde el Mac por USB o TCP/IP.",
              symbol: "iphone.gen3.radiowaves.left.and.right", install: .brewFormula("scrcpy"), category: .media),
    ]

    static func items(in category: CatalogCategory) -> [CatalogItem] {
        items.filter { $0.category == category }
    }

    static func contains(method: InstallMethod) -> Bool {
        items.contains { $0.install == method }
    }
}

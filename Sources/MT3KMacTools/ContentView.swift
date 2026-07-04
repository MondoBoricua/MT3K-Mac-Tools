import SwiftUI

struct ContentView: View {
    @EnvironmentObject var log: LogStore
    @EnvironmentObject var brew: BrewState
    @State private var selection: Pane = .browsers

    enum Pane: String, Hashable, CaseIterable, Identifiable {
        case browsers, apps, system, battery, flow, dev
        var id: String { rawValue }

        var title: String {
            switch self {
            case .browsers: return "Browsers"
            case .apps: return "Apps"
            case .system: return "Sistema"
            case .battery: return "Battery"
            case .flow: return "Flow"
            case .dev: return "Dev"
            }
        }

        var symbol: String {
            switch self {
            case .browsers: return "safari"
            case .apps: return "square.grid.2x2.fill"
            case .system: return "gearshape.2.fill"
            case .battery: return "battery.75percent"
            case .flow: return "mic.fill"
            case .dev: return "hammer.fill"
            }
        }
    }

    private let corePanes: [Pane] = [.browsers, .apps, .system]
    private let utilityPanes: [Pane] = [.battery, .flow]
    private let devPanes: [Pane] = [.dev]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    paneRows(corePanes)
                } header: {
                    brandHeader
                }
                Section("UTILITIES") {
                    paneRows(utilityPanes)
                }
                Section("DEVELOPER") {
                    paneRows(devPanes)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AuthorLinksView()
            }
        } detail: {
            ZStack {
                Theme.bgDark.ignoresSafeArea()
                switch selection {
                case .browsers: BrowsersView()
                case .apps: AppsView()
                case .system: SystemView()
                case .battery: BatteryGuardView()
                case .flow: FlowView()
                case .dev: DevView()
                }
            }
        }
        .task {
            await brew.refresh()
            log.append("MT3K Mac Tools listo.", level: .success)
            if !brew.brewInstalled {
                log.append("Homebrew no detectado — instalalo desde la tab Apps.", level: .warn)
            }
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.adjustable.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.gradient)
                VStack(alignment: .leading, spacing: 0) {
                    Text("MT3K Mac Tools").font(.headline)
                    Text("v1.0").font(.caption2).foregroundColor(Theme.textSecondary)
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func paneRows(_ panes: [Pane]) -> some View {
        ForEach(panes) { s in
            Label(s.title, systemImage: s.symbol)
                .tag(s)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.circle")
                .font(.system(size: 72))
                .foregroundStyle(Theme.gradient)
            Text(title).font(.largeTitle).bold()
            Text(subtitle)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(40)
    }
}

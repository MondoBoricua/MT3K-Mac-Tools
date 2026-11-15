import Foundation

/// Avisa cuando hay una versión más nueva publicada. Sólo consulta el tag del último
/// release público (una petición anónima a GitHub, como mucho una vez al día); la app
/// no se descarga ni se actualiza sola.
@MainActor
final class UpdateChecker: ObservableObject {
    static let downloadURL = URL(string: "https://www.patreon.com/MT3K")!
    private static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/MondoBoricua/MT3K-Mac-Tools/releases/latest")!
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "updateCheckLastDate"
    private static let latestVersionKey = "updateCheckLatestVersion"
    static let enabledKey = "updateCheckEnabled"

    /// Versión publicada más nueva que la instalada; nil si no hay o no se sabe.
    @Published private(set) var availableVersion: String?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func checkIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.enabledKey) as? Bool ?? true else {
            availableVersion = nil
            return
        }
        publish(defaults.string(forKey: Self.latestVersionKey))
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tag = Self.tagName(fromReleaseJSON: data) else { return }
        defaults.set(Date(), forKey: Self.lastCheckKey)
        defaults.set(tag, forKey: Self.latestVersionKey)
        publish(tag)
    }

    private func publish(_ tag: String?) {
        guard let tag, Self.isNewer(tag, than: currentVersion) else {
            availableVersion = nil
            return
        }
        availableVersion = Self.normalized(tag)
    }

    nonisolated static func tagName(fromReleaseJSON data: Data) -> String? {
        struct Release: Decodable { let tag_name: String }
        return (try? JSONDecoder().decode(Release.self, from: data))?.tag_name
    }

    nonisolated static func normalized(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    /// Compara versiones numéricas por componentes ("1.10" > "1.9", "1.1" == "1.1.0").
    /// Devuelve false si alguna no es una versión numérica válida.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ v: String) -> [Int]? {
            let pieces = normalized(v).split(separator: ".", omittingEmptySubsequences: false)
            let numbers = pieces.compactMap { Int($0) }
            return numbers.count == pieces.count && !numbers.isEmpty ? numbers : nil
        }
        guard let r = parts(remote), let l = parts(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}

import AppKit
import Foundation
import ServiceManagement

@MainActor
final class LoginItemState: ObservableObject {
    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var lastError = ""

    var isEnabled: Bool {
        status == .enabled
    }

    var isRunningFromApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    var statusText: String {
        switch status {
        case .enabled:
            return "Activo"
        case .requiresApproval:
            return "Requiere aprobar"
        case .notRegistered:
            return "Apagado"
        case .notFound:
            return "No disponible"
        @unknown default:
            return "Desconocido"
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) async {
        if enabled, !isRunningFromApplications {
            // Registering from dist/ leaves a broken login item once that copy is rebuilt.
            lastError = "Abre MT3K Mac Tools desde /Applications antes de activar el inicio automático (correrlo desde dist/ deja el item roto tras recompilar)."
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }
            lastError = ""
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

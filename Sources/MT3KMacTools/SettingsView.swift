import SwiftUI

struct SettingsView: View {
    @AppStorage("installBehavior") private var installBehavior = "ask"
    @AppStorage("showAdvancedTools") private var showAdvancedTools = true
    @AppStorage("confirmSecurityTools") private var confirmSecurityTools = true
    @AppStorage("terminalTimeoutMinutes") private var terminalTimeoutMinutes = 6.0
    @AppStorage("preferredTerminal") private var preferredTerminal = "Terminal"
    @AppStorage("menuMetricDiskEnabled") private var menuMetricDiskEnabled = false
    @AppStorage("menuMetricCPUEnabled") private var menuMetricCPUEnabled = false
    @AppStorage("menuMetricGPUEnabled") private var menuMetricGPUEnabled = false
    @AppStorage("menuMetricRAMEnabled") private var menuMetricRAMEnabled = false

    var body: some View {
        Form {
            Section("Instalación") {
                Picker("Apps ya instaladas", selection: $installBehavior) {
                    Text("Preguntar antes de reemplazar").tag("ask")
                    Text("Omitir").tag("skip")
                    Text("Reinstalar con --force").tag("force")
                }
                Toggle("Confirmar herramientas de ciberseguridad", isOn: $confirmSecurityTools)
                Toggle("Mostrar herramientas avanzadas", isOn: $showAdvancedTools)
            }

            Section("Barra de menús") {
                Toggle("Medidor de SSD", isOn: $menuMetricDiskEnabled)
                Toggle("Medidor de CPU", isOn: $menuMetricCPUEnabled)
                Toggle("Medidor de GPU", isOn: $menuMetricGPUEnabled)
                Toggle("Medidor de RAM", isOn: $menuMetricRAMEnabled)
                Text("Cada medidor aparece como ícono compacto arriba en la barra de menús.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Section("Terminal handoff") {
                Picker("Terminal preferido", selection: $preferredTerminal) {
                    Text("Terminal.app").tag("Terminal")
                    Text("iTerm").tag("iTerm")
                    Text("Ghostty").tag("Ghostty")
                }
                Slider(value: $terminalTimeoutMinutes, in: 2...15, step: 1) {
                    Text("Timeout")
                }
                Text("\(Int(terminalTimeoutMinutes)) minutos para detectar installs que abren Terminal.")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460, height: 520)
    }
}

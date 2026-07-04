// Lógica de decisión pura del Battery Guard — compartida entre el daemon
// (MT3KBatteryHelper) y los tests. Sin IOKit ni SMC: recibe el estado ya
// leído y devuelve la única escritura (si alguna) que corresponde.
//
// CONTRATO CRÍTICO: `onAC` debe ser presencia física del charger
// (`ExternalConnected` del AppleSmartBattery), NUNCA el estado IOPS de
// power-source. IOPS reporta "de dónde consume el sistema ahora", que macOS
// voltea a Battery Power mientras la carga está inhibida en el límite; leer
// eso como desconexión reanudaba la carga y la batería escalaba 80% → 99%.

public enum GuardAction: Equatable, Sendable {
    /// Pausar la carga: en AC, en o sobre el límite, y aún no inhibida.
    case inhibitCharging
    /// Reanudar la carga: charger desconectado o bajo el umbral de resume.
    case resumeCharging
    /// Sin escritura — el estado actual ya es el correcto.
    case none
}

public func guardAction(
    percent: Int,
    onAC: Bool,
    chargingInhibited: Bool,
    enabled: Bool,
    limit: Int,
    resume: Int,
    topUpActive: Bool = false
) -> GuardAction {
    guard enabled else { return .none }
    if topUpActive {
        // Top-up: el límite queda suspendido — sólo levantar el inhibit si sigue puesto.
        return chargingInhibited ? .resumeCharging : .none
    }
    if onAC && percent >= limit && !chargingInhibited {
        return .inhibitCharging
    }
    if (!onAC || percent <= resume) && chargingInhibited {
        return .resumeCharging
    }
    return .none
}

/// El top-up ("carga completa por hoy") termina al llegar a 100% o al
/// desconectar el charger — en ambos casos el guard vuelve a su límite normal.
public func topUpShouldEnd(percent: Int, onAC: Bool) -> Bool {
    percent >= 100 || !onAC
}

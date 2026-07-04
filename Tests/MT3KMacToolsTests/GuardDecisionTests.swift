import Testing
import BatteryGuardCore

// La lógica que corre como root y escribe SMC real. Cada caso raro aquí
// fue (o pudo ser) una batería cargando más allá del límite.
@Suite("Battery Guard — decisión del daemon")
struct GuardDecisionTests {
    @Test("Escenario del bug 80→99%: inhibido en el límite CON charger puesto NO reanuda")
    func holdsInhibitAtLimitOnAC() {
        // ExternalConnected=true aunque IOPS reporte "Battery Power" por la inhibición.
        let action = guardAction(percent: 80, onAC: true, chargingInhibited: true,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .none)
    }

    @Test("El mismo estado con onAC mal leído (IOPS) habría reanudado — el contrato importa")
    func iopsMisreadWouldResume() {
        // Documenta el bug: si onAC viniera del power-source state (false bajo
        // inhibición), la decisión sería .resumeCharging y la batería escala.
        let action = guardAction(percent: 80, onAC: false, chargingInhibited: true,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .resumeCharging)
    }

    @Test("En AC, en el límite, sin inhibir → pausa la carga")
    func inhibitsAtLimit() {
        let action = guardAction(percent: 80, onAC: true, chargingInhibited: false,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .inhibitCharging)
    }

    @Test("Sobre el límite (arrancó ya pasado) también pausa")
    func inhibitsAboveLimit() {
        let action = guardAction(percent: 93, onAC: true, chargingInhibited: false,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .inhibitCharging)
    }

    @Test("Charger desconectado estando inhibido → reanuda (para no bloquear la próxima carga)")
    func resumesWhenUnplugged() {
        let action = guardAction(percent: 78, onAC: false, chargingInhibited: true,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .resumeCharging)
    }

    @Test("Bajo el umbral de resume en AC estando inhibido → reanuda")
    func resumesBelowThresholdOnAC() {
        let action = guardAction(percent: 74, onAC: true, chargingInhibited: true,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .resumeCharging)
    }

    @Test("Zona muerta (entre resume y límite) inhibido en AC → mantiene, sin escritura")
    func deadZoneHolds() {
        let action = guardAction(percent: 77, onAC: true, chargingInhibited: true,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .none)
    }

    @Test("Bajo el límite sin inhibir → nada que hacer", arguments: [30, 74, 79])
    func belowLimitNoWrite(percent: Int) {
        let action = guardAction(percent: percent, onAC: true, chargingInhibited: false,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .none)
    }

    @Test("En batería (sin AC) y sin inhibir → nunca escribe")
    func onBatteryIdle() {
        let action = guardAction(percent: 85, onAC: false, chargingInhibited: false,
                                 enabled: true, limit: 80, resume: 75)
        #expect(action == .none)
    }

    @Test("Guard deshabilitado → nunca escribe, aunque esté inhibido")
    func disabledNeverWrites() {
        let action = guardAction(percent: 90, onAC: true, chargingInhibited: true,
                                 enabled: false, limit: 80, resume: 75)
        #expect(action == .none)
    }
}

@Suite("Battery Guard — top-up (carga completa por hoy)")
struct TopUpTests {
    @Test("Top-up activo estando inhibido en el límite → levanta el inhibit")
    func liftsInhibitDuringTopUp() {
        let action = guardAction(percent: 80, onAC: true, chargingInhibited: true,
                                 enabled: true, limit: 80, resume: 75, topUpActive: true)
        #expect(action == .resumeCharging)
    }

    @Test("Top-up activo sobre el límite sin inhibir → NO pausa (el límite está suspendido)")
    func doesNotInhibitAboveLimitDuringTopUp() {
        let action = guardAction(percent: 92, onAC: true, chargingInhibited: false,
                                 enabled: true, limit: 80, resume: 75, topUpActive: true)
        #expect(action == .none)
    }

    @Test("Top-up termina al llegar a 100%")
    func endsAtFull() {
        #expect(topUpShouldEnd(percent: 100, onAC: true))
    }

    @Test("Top-up termina al desconectar el charger")
    func endsOnUnplug() {
        #expect(topUpShouldEnd(percent: 88, onAC: false))
    }

    @Test("Top-up sigue mientras carga en AC bajo 100%", arguments: [80, 92, 99])
    func continuesWhileCharging(percent: Int) {
        #expect(!topUpShouldEnd(percent: percent, onAC: true))
    }

    @Test("Tras terminar el top-up (flag limpio) en 100% → vuelve a inhibir de inmediato")
    func rearmsAfterTopUp() {
        let action = guardAction(percent: 100, onAC: true, chargingInhibited: false,
                                 enabled: true, limit: 80, resume: 75, topUpActive: false)
        #expect(action == .inhibitCharging)
    }
}

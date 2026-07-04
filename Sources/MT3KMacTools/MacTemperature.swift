import Foundation
import os

/// Native Apple Silicon temperature reader via private IOHID APIs.
///
/// macOS expone los sensores de los SoC M-series como HID services en el
/// AppleVendor usage page (0xff00) / TemperatureSensor usage (0x0005).
/// Las funciones `IOHIDEventSystemClientCreate*` y `IOHIDServiceClientCopyEvent*`
/// son privadas, así que las cargamos vía `dlsym` contra el binario público
/// de IOKit.framework — sin necesidad de entitlements ni sudo.
///
/// Sensores de interés en chips M (varían por chip):
/// - `pACC MTR Temp Sensor#` → P-cores (performance cluster)
/// - `eACC MTR Temp Sensor#` → E-cores (efficiency cluster)
/// - `GPU MTR Temp Sensor#`  → GPU
/// - `NAND CH0 temp`         → SSD controller
///
/// Devolvemos el promedio de P-cores como "temperatura CPU" más útil.

enum MacTemperature {
    static let shared = MacTemperatureReader()
}

/// Promedios devueltos por una lectura.
struct TemperatureReading: Sendable {
    let cpuPerformanceC: Double    // Promedio P-cores (NaN si no hay sensor)
    let cpuEfficiencyC: Double     // Promedio E-cores
    let gpuC: Double               // Promedio GPU
    let cpuMaxC: Double            // Pico de todos los sensores CPU
    let allSensors: [String: Double]

    var available: Bool { !allSensors.isEmpty }

    /// Valor más útil para display: promedio P-cores si existe, si no la mayor lectura.
    var displayTemperatureC: Double? {
        if !cpuPerformanceC.isNaN { return cpuPerformanceC }
        if !cpuEfficiencyC.isNaN { return cpuEfficiencyC }
        if !cpuMaxC.isNaN { return cpuMaxC }
        return nil
    }
}

/// Cached, thread-safe wrapper que hace polling en background.
/// `current` devuelve la última lectura sin bloquear nunca.
final class MacTemperatureReader: @unchecked Sendable {

    // OSAllocatedUnfairLock disponible en macOS 13+. Es async-safe.
    private struct Cache: Sendable {
        var reading: TemperatureReading?
    }
    private let lock = OSAllocatedUnfairLock<Cache>(initialState: Cache())
    private let pollStarted = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// Última lectura cacheada. Returns nil hasta que el background poll capture la primera.
    var current: TemperatureReading? {
        lock.withLock { $0.reading }
    }

    /// Arranca el polling en background (idempotente — solo una vez por proceso).
    func startPolling(interval: TimeInterval = 5.0) {
        let alreadyStarted = pollStarted.withLock { started -> Bool in
            if started { return true }
            started = true
            return false
        }
        guard !alreadyStarted else { return }
        Task.detached(priority: .background) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let reading = self.readSynchronously() {
                    self.lock.withLock { $0.reading = reading }
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    /// API legacy compatible — devuelve la lectura cacheada (no bloquea nunca).
    /// La primera vez puede devolver nil; arranca el poll si no estaba corriendo.
    func read() -> TemperatureReading? {
        startPolling()
        return current
    }


    // MARK: - Private function pointers (resolved at init via dlsym)

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValueFn = @convention(c) (AnyObject, Int32) -> Double

    private let createClient: CreateFn?
    private let setMatching: SetMatchingFn?
    private let copyServices: CopyServicesFn?
    private let copyProperty: CopyPropertyFn?
    private let copyEvent: CopyEventFn?
    private let getFloatValue: GetFloatValueFn?

    // MARK: - Constants (Apple's HID page + usage codes)

    private static let kHIDPage_AppleVendor: Int32 = 0xff00
    private static let kHIDUsage_AppleVendor_TemperatureSensor: Int32 = 0x0005
    private static let kIOHIDEventTypeTemperature: Int64 = 15

    init() {
        // RTLD_DEFAULT busca en TODO el namespace dyld actual — IOKit ya está
        // linkeado por el framework público, así que los símbolos privados
        // están disponibles vía dlsym sin tener que dlopen explícito.
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        func lookup<T>(_ name: String) -> T? {
            guard let sym = dlsym(RTLD_DEFAULT, name) else { return nil }
            return unsafeBitCast(sym, to: T.self)
        }
        createClient = lookup("IOHIDEventSystemClientCreate")
        setMatching = lookup("IOHIDEventSystemClientSetMatching")
        copyServices = lookup("IOHIDEventSystemClientCopyServices")
        copyProperty = lookup("IOHIDServiceClientCopyProperty")
        copyEvent = lookup("IOHIDServiceClientCopyEvent")
        getFloatValue = lookup("IOHIDEventGetFloatValue")
    }

    /// `true` si todos los símbolos privados se resolvieron y el SoC es ARM.
    var available: Bool {
        guard createClient != nil, setMatching != nil, copyServices != nil,
              copyProperty != nil, copyEvent != nil, getFloatValue != nil else {
            return false
        }
        return isAppleSilicon()
    }

    private func isAppleSilicon() -> Bool {
        var size = 0
        sysctlbyname("hw.optional.arm64", nil, &size, nil, 0)
        guard size > 0 else { return false }
        var value: Int32 = 0
        sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return value == 1
    }

    /// SYNCHRONOUS: bloquea unas ms haciendo IOHID calls. Llamar SOLO desde el
    /// background poll, nunca desde un Task que también haga otros captures.
    private func readSynchronously() -> TemperatureReading? {
        guard available,
              let createClient, let setMatching, let copyServices,
              let copyProperty, let copyEvent, let getFloatValue else {
            return nil
        }

        guard let clientPtr = createClient(kCFAllocatorDefault) else { return nil }
        let client = clientPtr.takeRetainedValue()

        let matching: [String: Any] = [
            "PrimaryUsagePage": Self.kHIDPage_AppleVendor,
            "PrimaryUsage": Self.kHIDUsage_AppleVendor_TemperatureSensor
        ]
        setMatching(client, matching as CFDictionary)

        guard let servicesPtr = copyServices(client) else { return nil }
        let services = servicesPtr.takeRetainedValue() as [AnyObject]
        guard !services.isEmpty else { return nil }

        // Field selector: tipo << 16 (IOKit convention para IOHIDEventGetFloatValue).
        let fieldSelector: Int32 = Int32(Self.kIOHIDEventTypeTemperature << 16)

        var pCoreReadings: [Double] = []
        var eCoreReadings: [Double] = []
        var gpuReadings: [Double] = []
        var allCPUReadings: [Double] = []
        var allSensors: [String: Double] = [:]

        for service in services {
            // Cada service expone el campo "Product" con el nombre del sensor.
            guard let namePtr = copyProperty(service, "Product" as CFString) else { continue }
            let nameRef = namePtr.takeRetainedValue()
            guard let name = nameRef as? String else { continue }

            // Algunos sensores aún no tienen evento listo → devuelven nil.
            guard let eventPtr = copyEvent(service, Self.kIOHIDEventTypeTemperature, 0, 0) else { continue }
            let event = eventPtr.takeRetainedValue()
            let value = getFloatValue(event, fieldSelector)

            // 0°C indica sensor no soportado; descartamos.
            guard value > 0 else { continue }
            allSensors[name] = value

            let lower = name.lowercased()
            if lower.contains("pacc") || lower.hasPrefix("tp") || lower.contains("tdie") || lower.contains("tcal") {
                pCoreReadings.append(value)
                allCPUReadings.append(value)
            } else if lower.contains("eacc") || lower.hasPrefix("te") {
                eCoreReadings.append(value)
                allCPUReadings.append(value)
            } else if lower.contains("gpu") || lower.hasPrefix("tg") {
                gpuReadings.append(value)
            }
        }

        guard !allSensors.isEmpty else { return nil }

        func avg(_ vals: [Double]) -> Double {
            vals.isEmpty ? .nan : vals.reduce(0, +) / Double(vals.count)
        }

        return TemperatureReading(
            cpuPerformanceC: avg(pCoreReadings),
            cpuEfficiencyC: avg(eCoreReadings),
            gpuC: avg(gpuReadings),
            cpuMaxC: allCPUReadings.max() ?? allSensors.values.max() ?? .nan,
            allSensors: allSensors
        )
    }
}

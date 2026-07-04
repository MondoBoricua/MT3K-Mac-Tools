// MT3K Flow — modelos, providers, secrets (Keychain) y assets compartidos.
import AppKit
import ApplicationServices
import AVFoundation
import IOKit.hid
import Security
import SwiftUI


enum FlowProvider: String, CaseIterable, Identifiable {
    case local = "Local"
    case groq = "Groq"
    case openAI = "OpenAI"

    var id: String { rawValue }
}

enum FlowLanguage: String, CaseIterable, Identifiable {
    case automatic = "Auto"
    case spanish = "Español"
    case english = "English"
    case translateEnglish = "Translate"

    var id: String { rawValue }
}

enum FlowPermissionState: String {
    case granted = "Listo"
    case denied = "Denegado"
    case prompt = "Pedir permiso"
    case unknown = "Sin verificar"

    var ok: Bool { self == .granted }
}

enum FlowSecrets {
    private static let service = "com.mt3k.mac-tools.flow"

    static func account(for provider: FlowProvider) -> String {
        "api-key-\(provider.rawValue.lowercased())"
    }

    static func hasAPIKey(for provider: FlowProvider) -> Bool {
        guard provider != .local else { return false }
        var query = baseQuery(provider)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func apiKey(for provider: FlowProvider) -> String? {
        guard provider != .local else { return nil }
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveAPIKey(_ key: String, for provider: FlowProvider) throws {
        guard provider != .local else { return }
        let data = Data(key.utf8)
        let query = baseQuery(provider)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
            return
        }
        throw keychainError(status)
    }

    static func deleteAPIKey(for provider: FlowProvider) throws {
        guard provider != .local else { return }
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private static func baseQuery(_ provider: FlowProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider)
        ]
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        return NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: message])
    }
}

enum MT3KFlowAssets {
    static let icon: NSImage? = {
        let base = Bundle.main.url(forResource: "MT3KFlowIcon", withExtension: "png")
        let x2 = Bundle.main.url(forResource: "MT3KFlowIcon@2x", withExtension: "png")
        let x3 = Bundle.main.url(forResource: "MT3KFlowIcon@3x", withExtension: "png")

        guard let base, let image = NSImage(contentsOf: base) else { return nil }
        image.size = NSSize(width: 28, height: 42)
        if let x2, let rep = NSImage(contentsOf: x2)?.representations.first {
            image.addRepresentation(rep)
        }
        if let x3, let rep = NSImage(contentsOf: x3)?.representations.first {
            image.addRepresentation(rep)
        }
        return image
    }()
}


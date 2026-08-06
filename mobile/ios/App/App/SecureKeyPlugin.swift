import Capacitor
import Foundation

import LocalAuthentication
import Security

/// T-519 (DS-01) — thin Secure Enclave bridge used by the shared TypeScript SecureKey contract.
///
/// Secure Enclave has no HMAC key type. Both `deviceHmac(data)` and `hmac(data)` use deterministic
/// P-256 ECDH with their own public key and feed `data` as X9.63 shared info. They are deliberately
/// different keys: deviceHmac is ThisDeviceOnly + userPresence (biometry or device passcode), survives
/// biometric enrollment and protects WRAP_code recovery; hmac is biometryCurrentSet-bound for the
/// separate WRAP_bio. A third P-256 key signs §8 data.
@objc(SecureKeyPlugin)
public final class SecureKeyPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SecureKeyPlugin"
    public let jsName = "SecureKey"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "ensure", returnType: CAPPluginReturnPromise),

        CAPPluginMethod(name: "deviceHmac", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "hmac", returnType: CAPPluginReturnPromise),

        CAPPluginMethod(name: "resetBiometric", returnType: CAPPluginReturnPromise),

        CAPPluginMethod(name: "bootMarker", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sign", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "invalidate", returnType: CAPPluginReturnPromise),
    ]

    private static let deviceDeriveTag = Data("app.greenchat.securekey.device-derive.v1".utf8)
    private static let deriveTag = Data("app.greenchat.securekey.derive.v1".utf8)
    private static let signTag = Data("app.greenchat.securekey.sign.v1".utf8)
    private let operationQueue = DispatchQueue(
        label: "app.greenchat.securekey.operations",
        qos: .userInitiated
    )

    private enum SecureKeyError: LocalizedError {
        case osStatus(OSStatus, String)
        case security(String)

        var errorDescription: String? {
            switch self {
            case let .osStatus(status, operation):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "\(operation): \(detail)"
            case let .security(message):
                return message
            }
        }
    }

    private func accessControl(authBound: Bool, userPresence: Bool = false) throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if authBound {
            flags.insert(.biometryCurrentSet)
        } else if userPresence {
            // Recovery-key survives biometric enrollment and can fall back to the device passcode.
            flags.insert(.userPresence)
        }
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            flags,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? SecureKeyError.security("SecureKey: access control failed")
        }
        return access
    }

    private func lookupQuery(tag: Data, prompt: String? = nil, failWithoutUI: Bool = false) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let prompt {
            query[kSecUseOperationPrompt as String] = prompt
        }
        if failWithoutUI {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return query
    }

    private func ensureKey(tag: Data, authBound: Bool, userPresence: Bool = false) throws {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            lookupQuery(tag: tag, failWithoutUI: true) as CFDictionary,
            &item
        )
        if status == errSecSuccess || status == errSecInteractionNotAllowed {
            return
        }
        guard status == errSecItemNotFound else {
            throw SecureKeyError.osStatus(status, "SecureKey.ensure lookup")
        }

        let privateAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessControl as String: try accessControl(authBound: authBound, userPresence: userPresence),
        ]
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: privateAttributes,
        ]
        var error: Unmanaged<CFError>?
        guard SecKeyCreateRandomKey(attributes as CFDictionary, &error) != nil else {
            throw error?.takeRetainedValue() ?? SecureKeyError.security("SecureKey.ensure keygen failed")
        }
    }

    private func loadKey(tag: Data, prompt: String? = nil) throws -> SecKey {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookupQuery(tag: tag, prompt: prompt) as CFDictionary, &item)
        guard status == errSecSuccess, let item else {
            throw SecureKeyError.osStatus(status, "SecureKey key lookup")
        }
        return item as! SecKey
    }

    private func inputData(_ call: CAPPluginCall, method: String) throws -> Data {
        guard let encoded = call.getString("data"),
              let data = Data(base64Encoded: encoded),
              data.base64EncodedString() == encoded else {
            throw SecureKeyError.security("SecureKey.\(method): invalid base64 data")
        }
        return data
    }

    private func biometricErrorCode(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == LAError.errorDomain {
            if ns.code == LAError.userCancel.rawValue || ns.code == LAError.systemCancel.rawValue || ns.code == LAError.appCancel.rawValue {
                return "SecureKey.hmac: AUTH_CANCELLED"
            }
            if ns.code == LAError.biometryLockout.rawValue {
                return "SecureKey.hmac: AUTH_LOCKOUT"
            }
            if ns.code == LAError.authenticationFailed.rawValue {
                return "SecureKey.hmac: AUTH_FAILED"
            }
        }
        if ns.domain == NSOSStatusErrorDomain {
            if ns.code == Int(errSecUserCanceled) { return "SecureKey.hmac: AUTH_CANCELLED" }
            if ns.code == Int(errSecAuthFailed) { return "SecureKey.hmac: AUTH_FAILED" }
        }
        let text = error.localizedDescription.lowercased()
        if text.contains("lockout") || text.contains("locked out") { return "SecureKey.hmac: AUTH_LOCKOUT" }
        return "SecureKey.hmac failed: \(error.localizedDescription)"
    }

    @objc public func bootMarker(_ call: CAPPluginCall) {
        let bootEpochMinute = Int((Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime) / 60.0)
        call.resolve(["marker": "ios-epoch:\(bootEpochMinute)"])
    }

    @objc public func ensure(_ call: CAPPluginCall) {
        operationQueue.async {
            do {
                try self.ensureKey(tag: Self.deviceDeriveTag, authBound: false, userPresence: true)
                try self.ensureKey(tag: Self.signTag, authBound: false)
                call.resolve()
            } catch {
                call.reject("SecureKey.ensure failed: \(error.localizedDescription)")
            }
        }
    }

    @objc public func deviceHmac(_ call: CAPPluginCall) {
        operationQueue.async {
            var context = Data()
            var derived = Data()
            defer {
                context.resetBytes(in: 0..<context.count)
                derived.resetBytes(in: 0..<derived.count)
            }
            do {
                context = try self.inputData(call, method: "deviceHmac")
                try self.ensureKey(tag: Self.deviceDeriveTag, authBound: false, userPresence: true)
                let privateKey = try self.loadKey(
                    tag: Self.deviceDeriveTag,
                    prompt: "Подтвердите PIN, пароль или биометрию устройства для Green Chat"
                )
                guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                    throw SecureKeyError.security("SecureKey.deviceHmac: public key unavailable")
                }
                let algorithm = SecKeyAlgorithm.ecdhKeyExchangeStandardX963SHA256
                guard SecKeyIsAlgorithmSupported(privateKey, .keyExchange, algorithm) else {
                    throw SecureKeyError.security("SecureKey.deviceHmac: Secure Enclave ECDH unavailable")
                }
                let parameters: [SecKeyKeyExchangeParameter: Any] = [
                    .requestedSize: 32,
                    .sharedInfo: context,
                ]
                var error: Unmanaged<CFError>?
                guard let result = SecKeyCopyKeyExchangeResult(
                    privateKey,
                    algorithm,
                    publicKey,
                    parameters as CFDictionary,
                    &error
                ) as Data? else {
                    throw error?.takeRetainedValue()
                        ?? SecureKeyError.security("SecureKey.deviceHmac: key agreement failed")
                }
                derived = result
                guard derived.count == 32 else {
                    throw SecureKeyError.security("SecureKey.deviceHmac: derived secret is not 32 bytes")
                }
                call.resolve(["mac": derived.base64EncodedString()])
            } catch {
                call.reject("SecureKey.deviceHmac failed: \(error.localizedDescription)")
            }
        }
    }

    @objc public func hmac(_ call: CAPPluginCall) {
        operationQueue.async {
            var context = Data()
            var derived = Data()
            defer {
                context.resetBytes(in: 0..<context.count)
                derived.resetBytes(in: 0..<derived.count)
            }
            do {
                context = try self.inputData(call, method: "hmac")
                try self.ensureKey(tag: Self.deriveTag, authBound: true)
                let privateKey = try self.loadKey(
                    tag: Self.deriveTag,
                    prompt: "Подтвердите доступ к защищённому хранилищу Green Chat"
                )
                guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                    throw SecureKeyError.security("SecureKey.hmac: public key unavailable")
                }
                let algorithm = SecKeyAlgorithm.ecdhKeyExchangeStandardX963SHA256
                guard SecKeyIsAlgorithmSupported(privateKey, .keyExchange, algorithm) else {
                    throw SecureKeyError.security("SecureKey.hmac: Secure Enclave ECDH unavailable")
                }
                let parameters: [SecKeyKeyExchangeParameter: Any] = [
                    .requestedSize: 32,
                    .sharedInfo: context,
                ]
                var error: Unmanaged<CFError>?
                guard let result = SecKeyCopyKeyExchangeResult(
                    privateKey,
                    algorithm,
                    publicKey,
                    parameters as CFDictionary,
                    &error
                ) as Data? else {
                    throw error?.takeRetainedValue()
                        ?? SecureKeyError.security("SecureKey.hmac: key agreement failed")
                }
                derived = result
                guard derived.count == 32 else {
                    throw SecureKeyError.security("SecureKey.hmac: derived secret is not 32 bytes")
                }
                call.resolve(["mac": derived.base64EncodedString()])
            } catch {
                call.reject(self.biometricErrorCode(error))
            }
        }
    }

    @objc public func resetBiometric(_ call: CAPPluginCall) {
        operationQueue.async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: Self.deriveTag,
                kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                call.reject("SecureKey.resetBiometric failed: OSStatus \(status)")
                return
            }
            call.resolve()
        }
    }

    @objc public func sign(_ call: CAPPluginCall) {
        operationQueue.async {
            var message = Data()
            var signature = Data()
            defer {
                message.resetBytes(in: 0..<message.count)
                signature.resetBytes(in: 0..<signature.count)
            }
            do {
                message = try self.inputData(call, method: "sign")
                try self.ensureKey(tag: Self.signTag, authBound: false)
                let privateKey = try self.loadKey(tag: Self.signTag)
                let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
                guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
                    throw SecureKeyError.security("SecureKey.sign: P-256 unavailable")
                }
                var error: Unmanaged<CFError>?
                guard let result = SecKeyCreateSignature(privateKey, algorithm, message as CFData, &error) as Data? else {
                    throw error?.takeRetainedValue()
                        ?? SecureKeyError.security("SecureKey.sign: signing failed")
                }
                signature = result
                call.resolve(["signature": signature.base64EncodedString()])
            } catch {
                call.reject("SecureKey.sign failed: \(error.localizedDescription)")
            }
        }
    }

    @objc public func invalidate(_ call: CAPPluginCall) {
        operationQueue.async {
            do {
                for tag in [Self.deviceDeriveTag, Self.deriveTag, Self.signTag] {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassKey,
                        kSecAttrApplicationTag as String: tag,
                        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                    ]
                    let status = SecItemDelete(query as CFDictionary)
                    guard status == errSecSuccess || status == errSecItemNotFound else {
                        throw SecureKeyError.osStatus(status, "SecureKey.invalidate")
                    }
                }
                call.resolve()
            } catch {
                call.reject("SecureKey.invalidate failed: \(error.localizedDescription)")
            }
        }
    }
}

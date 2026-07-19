import Foundation
import Observation
import ServiceManagement

/// 用户设置。普通项进 UserDefaults;API Key 进 Keychain(legacy,§2.5)。
/// API Key 读取优先级:Keychain → 开发期环境变量 OPENAI_API_KEY(release build 忽略 env,grill #29)。
@MainActor
@Observable
public final class SettingsStore {
    public static let keychainService = "com.yujunzou.ai-voice-input"
    public static let keychainAccount = "openai_api_key"

    private enum Key {
        static let model = "model"
        static let injectionMethod = "injectionMethod"
        static let autoPunctuation = "autoPunctuation"
        static let removeFillers = "removeFillers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults: UserDefaults

    /// release build 是否允许 env fallback(默认否;dev 用 AIVI_ALLOW_ENV_KEY=1 开)
    private static var envKeyAllowed: Bool {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["AIVI_ALLOW_ENV_KEY"] == "1"
        #endif
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.model: "gpt-4o-transcribe",
            Key.autoPunctuation: true,
            Key.removeFillers: false,
            Key.hotkeyKeyCode: Int(Hotkey.defaultToggle.keyCode),
            Key.hotkeyModifiers: Int(Hotkey.defaultToggle.carbonModifiers),
            Key.injectionMethod: "auto",
        ])
    }

    // MARK: - API Key(Keychain,绝不进 UserDefaults/plist)

    public var apiKey: String? {
        get { KeychainHelper.read(service: Self.keychainService, account: Self.keychainAccount) }
        set {
            if let newValue, !newValue.isEmpty {
                try? KeychainHelper.save(newValue, service: Self.keychainService, account: Self.keychainAccount)
            } else {
                KeychainHelper.delete(service: Self.keychainService, account: Self.keychainAccount)
            }
        }
    }

    /// 实际生效的 key:Keychain 优先,dev 期回落 env
    public var effectiveAPIKey: String {
        if let stored = apiKey, !stored.isEmpty { return stored }
        if Self.envKeyAllowed { return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "" }
        return ""
    }

    /// UI 展示用:只露尾 4 位
    public var apiKeyMasked: String {
        let key = apiKey ?? ""
        guard key.count > 4 else { return key.isEmpty ? "(未设置)" : "••••" }
        return "••••" + key.suffix(4)
    }

    // MARK: - 普通设置

    public var model: String {
        get { defaults.string(forKey: Key.model) ?? "gpt-4o-transcribe" }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    public var injectionMethod: String {
        get { defaults.string(forKey: Key.injectionMethod) ?? "auto" }
        set { defaults.set(newValue, forKey: Key.injectionMethod) }
    }

    public var autoPunctuation: Bool {
        get { defaults.bool(forKey: Key.autoPunctuation) }
        set { defaults.set(newValue, forKey: Key.autoPunctuation) }
    }

    public var removeFillers: Bool {
        get { defaults.bool(forKey: Key.removeFillers) }
        set { defaults.set(newValue, forKey: Key.removeFillers) }
    }

    public var hotkey: Hotkey {
        get {
            Hotkey(
                keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotkeyModifiers)
        }
    }

    // MARK: - 开机自启(grill #20,SMAppService 原生 macOS 13+)

    public var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Log.app.error("launchAtLogin toggle failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
